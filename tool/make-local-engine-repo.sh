#!/usr/bin/env bash
# Builds a local Maven mirror of the Flutter engine artifacts.
#
# Why: the `io.flutter:<abi>_debug` jars are published only to
# storage.googleapis.com. Where that host is unreachable, and those jars are not in
# the Gradle cache, every Android build hangs part-way through dependency resolution
# instead of failing fast. The same jars are already on disk inside the Flutter SDK,
# so the coordinates can be assembled locally and the build needs no network.
#
# Idempotent. `android/build.gradle.kts` adds the mirror only when this has been run,
# so a machine that does not need it never sees it.
#
# Override the location with BCODE_LOCAL_ENGINE_REPO (the Gradle build reads the same
# variable, falling back to android/local-engine-repo).
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER_SDK="${FLUTTER_SDK:-$(cat android/local.properties | sed -n 's/^flutter.sdk=//p')}"
ENGINE="$FLUTTER_SDK/bin/cache/artifacts/engine"
REPO="${BCODE_LOCAL_ENGINE_REPO:-android/local-engine-repo}"
# Absolute, because the repack step runs from a scratch directory and a relative
# output path would not resolve from there.
mkdir -p "$REPO"
REPO="$(cd "$REPO" && pwd)"
HASH="$(cat "$FLUTTER_SDK/bin/internal/engine.version")"
GRADLE_CACHE="$HOME/.gradle/caches/modules-2/files-2.1/io.flutter"

[ -d "$ENGINE" ] || { echo "Flutter engine artifacts not found at $ENGINE" >&2; exit 1; }

# The published per-ABI artifacts are thin: native libraries only, no classes. The
# SDK's flutter.jar is the fat embedding jar, so it cannot be used as-is — four copies
# of it on the classpath fail the duplicate-class check. Each entry below is therefore
# repacked with just its own ABI's libflutter.so.
#
#   coordinate                 SDK directory     jar entry
thin_abi() {
  local coordinate="$1" sdkdir="$2" abi="$3"
  local out="$REPO/io/flutter/$coordinate/1.0.0-$HASH"
  local work; work="$(mktemp -d)"
  mkdir -p "$out" "$work/lib/$abi"
  unzip -p "$ENGINE/$sdkdir/flutter.jar" "lib/$abi/libflutter.so" > "$work/lib/$abi/libflutter.so"
  rm -f "$out/$coordinate-1.0.0-$HASH.jar"
  # Stored rather than deflated: a ~390 MB native library compresses poorly and this
  # keeps the rebuild fast.
  (cd "$work" && zip -0 -q "$out/$coordinate-1.0.0-$HASH.jar" "lib/$abi/libflutter.so")
  rm -rf "$work"
  # Gradle needs the module descriptor as well as the artifact; take the real one
  # from the Gradle cache so the coordinates match the published module exactly.
  local pom; pom="$(find "$GRADLE_CACHE/$coordinate" -name '*.pom' 2>/dev/null | head -1 || true)"
  if [ -n "$pom" ]; then
    cp "$pom" "$out/$coordinate-1.0.0-$HASH.pom"
  else
    echo "  MISSING pom for $coordinate in $GRADLE_CACHE" >&2
    exit 1
  fi
  echo "  $coordinate  ($(du -h "$out/$coordinate-1.0.0-$HASH.jar" | cut -f1))"
}

echo "engine $HASH  ->  $REPO"

thin_abi armeabi_v7a_debug android-arm armeabi-v7a
thin_abi arm64_v8a_debug   android-arm64 arm64-v8a
thin_abi x86_64_debug     android-x64    x86_64

# The embedding artifact is a normal fat jar (classes plus nothing ABI-specific) and
# is already in the Gradle cache, so it is copied across rather than repacked.
embedding_jar="$(find "$GRADLE_CACHE/flutter_embedding_debug" -name '*.jar' 2>/dev/null | head -1 || true)"
embedding_pom="$(find "$GRADLE_CACHE/flutter_embedding_debug" -name '*.pom' 2>/dev/null | head -1 || true)"
if [ -n "$embedding_jar" ] && [ -n "$embedding_pom" ]; then
  d="$REPO/io/flutter/flutter_embedding_debug/1.0.0-$HASH"
  mkdir -p "$d"
  cp "$embedding_jar" "$d/flutter_embedding_debug-1.0.0-$HASH.jar"
  cp "$embedding_pom" "$d/flutter_embedding_debug-1.0.0-$HASH.pom"
  echo "  flutter_embedding_debug (from Gradle cache)"
else
  # Without this the build cannot compile any plugin module, so it is fatal rather
  # than a warning.
  echo "  MISSING flutter_embedding_debug in $GRADLE_CACHE" >&2
  echo "  It ships with any previous successful build; run one, or copy it from" >&2
  echo "  another machine's Gradle cache." >&2
  exit 1
fi

echo "done. android/build.gradle.kts picks this up automatically."
