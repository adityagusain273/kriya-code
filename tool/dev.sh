#!/usr/bin/env bash
# Build, install and launch B Code on the connected device in one step.
#
#   tool/dev.sh              debug build -> install -> launch
#   tool/dev.sh run          same, via `flutter run` for hot reload (press r)
#   tool/dev.sh test         analyze + full test suite
#   tool/dev.sh release      release APK (requires GITHUB_CLIENT_ID)
#
# GITHUB_CLIENT_ID is optional for debug builds: the app starts without it and
# reports GitHub sign-in as unavailable. Export it to exercise sign-in.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID=com.bcode.editor
APK=build/app/outputs/flutter-apk/app-debug.apk

defines=()
[ -n "${GITHUB_CLIENT_ID:-}" ] && defines+=("--dart-define=GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID")

device() {
  adb devices | awk 'NR>1 && $2=="device" {print $1; exit}'
}

case "${1:-dev}" in
  test)
    flutter analyze
    flutter test
    ;;

  run)
    exec flutter run "${defines[@]}" "${@:2}"
    ;;

  release)
    if [ -z "${GITHUB_CLIENT_ID:-}" ]; then
      echo "release builds need GITHUB_CLIENT_ID; refusing to ship one that cannot sign in" >&2
      exit 1
    fi
    # Crash symbolication hinges on build/symbols/ surviving every release
    # build. The flutter build system tracks its AOT outputs in
    # .dart_tool/flutter_build, not in build/: when build/ is wiped while that
    # cache is warm, gen_snapshot is skipped and an obfuscated APK ships with
    # no way to symbolicate its crash reports. Clear the cache whenever the
    # symbol files are missing so the rebuild regenerates them.
    symbols_ok() {
      ls build/symbols/app.android-*.symbols >/dev/null 2>&1
    }
    symbols_ok || rm -rf .dart_tool/flutter_build
    flutter build apk --release --obfuscate --split-debug-info=build/symbols "${defines[@]}"
    if ! symbols_ok; then
      echo "release build left no Dart symbol files; clearing the flutter build cache and rebuilding" >&2
      rm -rf .dart_tool/flutter_build
      flutter build apk --release --obfuscate --split-debug-info=build/symbols "${defines[@]}"
      symbols_ok || {
        echo "release produced no build/symbols/*.symbols; crash reports would be unsymbolicable" >&2
        exit 1
      }
    fi
    echo "==> Dart symbols: $(ls build/symbols/app.android-*.symbols | tr '\n' ' ')"
    ;;

  dev|*)
    serial="$(device)"
    [ -n "$serial" ] || { echo "no device connected" >&2; exit 1; }

    echo "==> building"
    flutter build apk --debug "${defines[@]}"

    echo "==> installing on $serial"
    adb -s "$serial" install -r "$APK" >/dev/null

    echo "==> launching"
    adb -s "$serial" shell am force-stop "$APP_ID"
    adb -s "$serial" shell monkey -p "$APP_ID" \
      -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

    # Poll rather than sleeping a fixed amount: a cold start on a slow device or
    # emulator can take the best part of half a minute, and a fixed short wait
    # reports a working build as a failure.
    for _ in $(seq 1 40); do
      sleep 2
      focus="$(adb -s "$serial" shell dumpsys window 2>/dev/null \
        | grep -m1 mCurrentFocus || true)"
      case "$focus" in
        *"$APP_ID"*) echo "==> ready: $focus"; exit 0 ;;
      esac
    done
    echo "==> app did not reach the foreground in 80s; last focus: ${focus:-none}" >&2
    echo "==> check 'adb -s $serial logcat'" >&2
    exit 1
    ;;
esac