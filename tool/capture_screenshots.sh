#!/usr/bin/env bash
# Capture the three Play Store screenshots from a connected device.
#
#   tool/capture_screenshots.sh            # all three, into store/screenshots/
#   tool/capture_screenshots.sh edit run   # only the ones named
#
# Shot 3 (GitHub) needs a build with GITHUB_CLIENT_ID compiled in and an account
# signed in on the device; it fails with a clear message otherwise rather than
# writing a screenshot of the sign-in screen.
#
# The device is driven by UI text, not by coordinates: a status-bar height or a
# font-scale change would otherwise silently shift every tap. Requires only
# adb and python3 (no extra pip packages).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID=com.bcode.editor
OUT=store/screenshots
SERIAL="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
[ -n "$SERIAL" ] || { echo "no device connected" >&2; exit 1; }
A=(adb -s "$SERIAL")
W="${CAPTURE_WIDTH:-720}"

mkdir -p "$OUT"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Dump the current UI hierarchy, retrying: `uiautomator dump` intermittently
# returns an empty hierarchy on this device ("could not get idle state").
dump_ui() {
  local out="$1" i
  for i in 1 2 3; do
    "${A[@]}" shell uiautomator dump "/sdcard/$out.xml" >/dev/null 2>&1
    "${A[@]}" pull "/sdcard/$out.xml" "$tmp/$out.xml" >/dev/null 2>&1 || true
    if [ -s "$tmp/$out.xml" ] && grep -q "<node " "$tmp/$out.xml"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Poll the UI hierarchy until $1 appears (or 15 s pass) — a cold start on this
# device can take 4 s, and a fixed sleep reports a working build as broken.
ui_has() {
  local needle="$1" i
  for i in $(seq 1 30); do
    if dump_ui "$2" && grep -qF "$needle" "$tmp/$2.xml"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# Tap the centre of the first node whose text or content-desc matches $1.
tap_text() {
  local needle="$1" coords
  dump_ui ui-tap || { echo "could not read the UI hierarchy" >&2; return 1; }
  coords="$(python3 "$(dirname "$0")/ui_tap_point.py" "$tmp/ui-tap.xml" "$needle")" || {
    echo "no UI element matching '$needle'" >&2; return 1; }
  "${A[@]}" shell input tap $coords
}

# The app draws edge-to-edge: status bar 0-72, content 72-1448, nav bar below.
# Play wants 16:9 or 9:16; 720x1280 starting below the status bar is exactly 9:16
# and keeps the app bar, the editor/console and the shortcut bar in frame.
shoot() {
  local name="$1"
  "${A[@]}" exec-out screencap -p > "$tmp/$name.png"
  if python3 -c "import PIL" 2>/dev/null; then
    CAPTURE_WIDTH="$W" OUT="$OUT" SRC="$tmp/$name.png" python3 - <<'PY'
import os
from PIL import Image
im = Image.open(os.environ['SRC']).convert('RGB')
w, h = im.size
top = min(72, h // 8)          # status bar
bottom = min(h, top + int(w * 16 / 9))
im.crop((0, top, w, bottom)).save(os.path.join(os.environ['OUT'], 'tmp.png'), optimize=True)
PY
    mv "$OUT/tmp.png" "$OUT/$name.png"
  else
    cp "$tmp/$name.png" "$OUT/$name.png"
    echo "   (pillow missing: saved uncropped)"
  fi
  echo "==> $OUT/$name.png"
}

launch() {
  "${A[@]}" shell am force-stop "$APP_ID"
  "${A[@]}" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  ui_has "Run code" ui-launch || { echo "app did not reach the editor" >&2; exit 1; }
}

shot_edit() {
  launch
  # Close the welcome tab's extra tabs so the file name and one clean file show.
  ui_has "showcase.py" ui-edit || ui_has "main.py" ui-edit || {
    echo "no file open in the editor" >&2; return 1; }
  sleep 1
  shoot 01_edit
}

shot_run() {
  ui_has "Run code" ui-run || launch
  tap_text "Run code" || return 1
  # A cold runtime can take a few seconds to print; wait for the first output line
  # rather than guessing.
  ui_has "Output" ui-run || { echo "console did not open" >&2; return 1; }
  sleep 4
  shoot 02_run
}

shot_github() {
  # Always relaunch: the Run shot leaves the console open, and the app bar it
  # covers is where the menu lives. A fresh launch is the reliable reset.
  launch
  # The launch animation swallows taps for a moment after the first frame, so a
  # single tap can silently do nothing. Tap until the menu's own item appears.
  local i
  for i in 1 2 3 4 5; do
    sleep 2
    tap_text "More actions" || continue
    if ui_has "Git &amp; GitHub" ui-gh2; then
      break
    fi
  done
  ui_has "Git &amp; GitHub" ui-gh2 || {
    echo "Git & GitHub is missing from the menu" >&2; return 1; }
  tap_text "Git" || return 1
  sleep 3
  if ui_has "Sign in with GitHub" ui-gh3; then
    echo "SKIP 03_github: this build has no GITHUB_CLIENT_ID, or no account is signed in." >&2
    echo "      Build with --dart-define=GITHUB_CLIENT_ID=<id>, sign in, then re-run." >&2
    return 1
  fi
  # Repo browser -> first repo -> Clone/Open Cloned Copy -> the Git panel.
  tap_text "Clone to Workspace" || tap_text "Open Cloned Copy" || return 1
  sleep 6
  ui_has "Commit" ui-gh4 || { echo "git workspace did not open" >&2; return 1; }
  tap_text "view diff" || true
  sleep 2
  shoot 03_github
}

if [ $# -eq 0 ]; then
  targets=(edit run github)
else
  targets=("$@")
fi
for t in "${targets[@]}"; do
  case "$t" in
    edit)   shot_edit ;;
    run)    shot_run ;;
    github) shot_github ;;
    *) echo "unknown shot '$t' (edit|run|github)" >&2; exit 1 ;;
  esac
done