# Store screenshots

Play requires at least two phone screenshots; B Code ships three, each one
proving one claim on the listing. They are captured from the real build, not
mocked.

| File | Claim it proves | What must be visible |
|---|---|---|
| `store/screenshots/01_edit.png` | "Full-featured mobile code editor" | Syntax-coloured Python, line numbers, file name and language in the status bar, tab strip |
| `store/screenshots/02_run.png` | "Run your code locally" | The same file, console open at the bottom with program output and the runtime version |
| `store/screenshots/03_github.png` | "GitHub integration" | The Git panel with changed files (or a diff), Pull / Commit / Push visible |

## Capturing

```bash
tool/capture_screenshots.sh            # all three
tool/capture_screenshots.sh edit run   # a subset
```

What it needs: a device over adb, `python3`, and Pillow (`pip install pillow`)
for the crop. Without Pillow it still writes the full-screen capture and says
so.

How it works, and why it is written this way:

- **Drives by UI text, not coordinates.** Every tap resolves the centre of a
  node by its `content-desc`/`text` from `uiautomator dump`. A status-bar
  height change, a different font scale or a new button in the app bar would
  silently shift a hard-coded tap onto the wrong control.
- **Polls instead of sleeping.** `ui_has` re-dumps for up to 15 s, because a
  cold start on this device takes 4 s and a fixed sleep reports a working build
  as broken.
- **Retries the dump.** `uiautomator dump` intermittently returns an empty
  hierarchy on this device; `dump_ui` re-dumps up to three times before
  believing it.
- **Crops to 9:16.** The app draws edge to edge: status bar 0–72, content
  72–1448, navigation bar below. The script crops `(0, 72, 720, 1352)`, i.e.
  720×1280, which keeps the app bar, the editor or console and the shortcut bar
  in frame and drops the system UI. Play accepts 16:9 or 9:16, so no padding or
  background mock-up is needed.
- **Re-launches for the GitHub shot.** The Run shot leaves the console open,
  and the console covers the app bar the overflow menu lives in. A fresh launch
  is the reliable reset. The first tap after launch can still be swallowed by
  the launch animation, so it taps "More actions" and re-checks for the menu
  item up to five times.

## The GitHub shot needs a real client id

`03_github.png` cannot be captured from a plain debug build: sign-in reports
"GitHub sign-in is not available in this build" without a compiled-in client id,
by design (`lib/core/constants.dart`). The script detects that screen and exits
with a SKIP line instead of writing a screenshot of the sign-in prompt.

To capture it:

```bash
flutter build apk --debug --dart-define=GITHUB_CLIENT_ID=<your GitHub OAuth app client id>
adb install -r build/app/outputs/flutter-apk/app-debug.apk
# sign in on the device once (GitHub → Continue with GitHub, approve in a browser)
tool/capture_screenshots.sh github
```

The same applies to a release build from CI, which passes
`secrets.BCODE_CLIENT_ID`.

If the signed-in account has no repository, the Git panel opens empty. Clone
any small repo first (the one the extension index lives in works), make one
edit, then re-run the shot.

## What each screenshot must show, in detail

**01_edit** — a Python file with a class, a decorator and a multi-line string,
which is what makes the highlighting legible at phone size: `showcase.py` in the
app's private workspace. Requirements: line numbers visible in the gutter, the
tab strip showing the file, `Ln 1, Col 1` and `25 lines` in the status bar, and
`python` in the language slot. Nothing else open, no console.

**02_run** — the same file after tapping Run. Requirements: the console header
with `Output` / `Terminal` tabs, at least one line of the program's own output,
and the runtime version line (`Python 3.14`). No error text, no download sheet.

**03_github** — the Git panel. Requirements: at least one changed file listed,
`Pull` / `Commit` / `Push` visible. Prefer a state with the diff open (`view
diff`) if the patch fits on screen, otherwise the file list is enough.

## Re-checking them before an upload

The screenshots are part of the listing and go stale with any UI change. Before
each upload: re-run the script, then look at all three and confirm the claims
above. Do not hand-edit them to hide a regression — fix the regression.

Device used for the current set: Realme C25 (RMX2193), Android 11, 720×1600 @
320 dpi, build 1.0.0+10 (debug, profiled as the same UI).