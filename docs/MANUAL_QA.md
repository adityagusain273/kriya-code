# B Code — Manual QA (pre-submission)

Every release build goes through this list before it is uploaded. Each item
names the screen and what "pass" means, so any tester can run it without
knowing the codebase.

**Setup:** fresh install (`adb install -r app-release.apk` or Play
internal-testing track). Do not restore app data from another device.

## 1. First launch
- [ ] App opens to the editor within ~3 s with no blank screen.
- [ ] Onboarding appears on first run; picking any languages creates files.
- [ ] Android 11+: no permission dialog appears. (See note — all-files access
      was deliberately removed; the share-with-Termux toggle is gone from
      Settings.)

## 2. Editor
- [ ] Create file, type, save (autosave interval respected), rename from
      explorer.
- [ ] Open several tabs and rotate the screen — tabs and scroll survive.
- [ ] Close tab / Close All from the command palette asks to save unsaved
      buffers, never crashes, and drops the right tab count.
- [ ] Drawer opens from the titlebar (previously this was broken in
      production builds).

## 3. Execution
- [ ] `print("hi")` in Python/Node runs and output appears in console.
- [ ] A crashing program shows the exit code and stack, not a frozen tab.
- [ ] Long output (e.g. `seq 1 200000`) does not hang or OOM the app.

## 4. Git
- [ ] Connect GitHub (device flow). Sign-in works with a real OAuth app id;
      SIGN-IN SHOULD NEVER show "unavailable" (that means the
      `GITHUB_CLIENT_ID` dart-define was lost in the build).
- [ ] Clone a small repo, commit, push, confirm on github.com.
- [ ] Reason view shows diffs; files open without breaking the tab list.

## 5. Preview / live server
- [ ] Preview HTML file: page loads inside the app.
- [ ] Live server: run + reload edits. Stop server: page unreachable.
- [ ] Turn Wi-Fi off — editing still works (offline-first).

## 6. Runtimes / Termux
- [ ] Download a runtime from the package manager on a metered connection —
      download works over TLS without errors (pins must not reject).
- [ ] With Termux installed: permission appears, RUN_COMMAND reaches Termux;
      concurrent commands in two terminal tabs do not cross their outputs
      (result request_ids no longer collide).

## 7. Settings
- [ ] Font size, theme, autosave, syntax theme persist after "Clear from
      recents"-then-reopen.
- [ ] Report a Bug: dialog lists chosen screenshots by name; sends the
      pre-filled email with the local crash log; no crash without
      attachments.
- [ ] Privacy → **Write crash log** off: trigger an error (open a broken file,
      or run code that throws), then check `adb shell run-as com.bcode.editor
      cat app_flutter/crash.log` — the new error must not appear. On again, the
      next error must appear. This toggle was a no-op before 2026-11-13.

## 8. Store compliance
- [ ] `store/screenshots/01_edit.png` and `02_run.png` are captures of this
      build, not an older one (`bash tool/capture_screenshots.sh edit run`
      reproduces them; the date on the file must match the build).
- [ ] `03_github.png` captured from a build with `GITHUB_CLIENT_ID` compiled in
      and an account signed in, showing at least one changed file plus
      Pull / Commit / Push. Not capturable from a plain debug build.
- [ ] `store/data_safety.md` re-read against the code: every host in the
      network table still exists and no new one was added.
- [ ] `https://adityagusain273.github.io/b-code/privacy_policy.html` returns
      200 and its "Last updated" date matches the local `store/privacy_policy.html`
      (the two drift if the page is not republished).
- [ ] `https://github.com/adityagusain273/b-code/issues` opens (not 404).
- [ ] The listing's support email is one that is actually read.
- [ ] Content-rating answers in `store/data_safety.md` re-checked after any
      feature that adds sharing, chat, purchases or a browser.

## 9. Stability sweep (10 min, no interaction)
- [ ] No uncaught exception in `adb logcat` (crash reporter would catch it).
- [ ] Battery drain consistent with background editor (no runaway timer).

## Release paths
- [ ] APK from CI installs and launches (GITHUB signed with the release key).
- [ ] `.aab` confirmed by bundletool → test-track install → same smoke list.
- [ ] RASP: installing a re-signed APK (modified signature) shows the
      signature notice but the app does not brick (no silent exit).

## Measurements — 2026-11-13

Device: Realme C25 (RMX2193), MediaTek MT6769V/CZ, arm64-v8a, 3.7 GB RAM,
Android 11 (API 30), 720×1600 @ 320 dpi. Installed build:
`com.bcode.editor` 1.0.0 (versionCode 10).

Build: profile APK (`flutter build apk --profile -Pbcode.sideload=true`),
`build/app/outputs/flutter-apk/app-profile.apk` (not the release artifact).

| Measurement | Result | Target |
|---|---|---|
| Cold start, warm (`am start -W TotalTime`) | 1618–1663 ms (5 runs); 1723 ms, 1902 ms later runs | < 3 s |
| Cold start, first launch after install | 4022 ms, 4706 ms | < 3 s |
| Idle PSS, app at rest (3-tab session, 2001-line file open) | 147.8–160.2 MB | < 250 MB |
| Worst frame, scrolling 2001-line Python file | 83.8 ms (p50 ≈ 28 ms, ~27 fps) | ≤ 32 ms |

The scroll target is missed. The frame pacing sits around 27–28 fps while
scrolling a 2001-line file, with one 83.8 ms stall, so the 32 ms ceiling is
exceeded both at the median and at the tail. This is measured on the profile
build, so it is not a debug-only artifact. Profiling before changing anything
is the next step; the likely candidates are whole-file tokenization on the UI
isolate and the per-frame bracket pass in `BCodeController.buildTextSpan`.

### Scroll profile, 2026-11-13 (after the gutter change)

Same device and build type. Frames were timed inside the app with
`SchedulerBinding.addTimingsCallback`; `totalSpan` is build start to raster
finish, which is stricter than the frame numbers the earlier pass recorded, so
compare the *change*, not the absolute value against the 83.8 ms row above. The
callback was the only thing added for the measurement and it is not in the
shipped tree (it costs microseconds per frame).
The scroll was a repeated 600 px fling (200 ms per swipe, 100 ms apart) over a
2001-line Python file.

| Measurement | Before | After | Target |
|---|---|---|---|
| Average UI build per frame | 32.0 ms | 15.3 ms | — |
| Average raster per frame | 13.5 ms | 10.0 ms | — |
| Typical frame (build + raster) | ~46 ms | ~25 ms | ≤ 32 ms |
| Worst frame | 75 ms | 40–52 ms | ≤ 32 ms |

What the profile ruled out:

- **Whole-file tokenization and the bracket pass are not on the scroll path.**
  `BCodeController.buildTextSpan` was called **0 times per frame** while
  scrolling (4 calls total, ~1.1 ms each, on the frame that opened the file).
  `highlight.parse` and `_colorizeBrackets` run on text change only.
- **The cost was proportional to the number of lines in the file**, not to the
  number of tokens. With the gutter out of the picture, a 2001-line file that had
  no grammar at all measured 12.5 ms of build against 13.5 ms for the highlighted
  one, and 200 lines measured 6.9 ms. Token count makes no difference; line count
  does.
- **The line-number gutter was the single biggest line item.** The package builds
  it as a `Table` with one row per line (2001 rows, ~8000 widgets), all walked on
  every repaint. Turning it off took the 2001-line build from 32.0 ms to 14.0 ms
  and the raster from 13.5 ms to 9.3 ms. `lib/editor/line_number_gutter.dart`
  replaces it with a `CustomPainter` that lays out only the ~25 visible numbers
  (~1.8 ms of build).

What is left: the remaining ~13.5 ms of UI build is Flutter painting the
whole-file paragraph inside `EditableText` (`RenderEditable` → `TextPainter`).
That cost is per line in the file, not per visible line, and no Dart-level change
in this app can cut it. Closing the last gap means rendering a window of lines
instead of one 2001-line paragraph (the `re_editor` / virtualized-editor
approach), which is a different piece of work from this item.

Also measured on this build: cold start 1771 ms (force-stopped relaunch with the
session restored; two later runs on a warm, throttled device read 3017 ms and
3661 ms, so the cold-start number is the noisy one here), idle PSS 157 MB with
one 2001-line tab open, 137 MB with a 9-line file.

## Manual checks for the extension and export work

- [x] Extensions → Community lists the four official packages (Rust, Go,
      Kotlin, Rails) from the published index, with no source error. The
      official source appears once under Sources and can be removed.
- [x] Get on Rust → preview shows version, author, language `.rs`, snippet and
      theme counts, and the README.
- [x] Install Rust → a `.rs` file reads `rust` in the status bar (grammar
      active, no reopen). Remove it → the same open tab reads `Plain Text`
      immediately, with no restart prompt.
- [ ] Cancel on the preview leaves nothing installed (covered by the unit
      test; not re-run on the device this pass).
- [ ] Bundled Python highlighting still works after removing an extension.
- [x] Export project → Include .git → verified on device: the saved zip
      contains `projects/` plus `.git/` with `HEAD` and `refs/`.
- [x] Export project → Skip .git → verified on device: the zip has no `.git`
      entries at all, directory entries included.
- [x] Export → Unzip Project on the same archive → the tree comes back with
      `.git` and the nested `Python projects/` folder, opened by the explorer
      without a restart.
- [x] Dismiss the save dialog → the temporary zip is deleted from the
      workspace; no `projects.zip` is left in the explorer.
- [x] Scroll a 2000-line file in a profile build → worst frame 83.8 ms
      (target ≤ 32 ms). Recorded above.
- [x] Line numbers still line up with the code after the viewport-only gutter
      replaced the package's per-line table (manual eye-check: numbers on the
      right, one per line, no drift after scrolling to the bottom of a 2001-line
      file).
- [x] Turn line numbers off in Settings → the code moves back to the left edge
      with no leftover column.
- [x] Word wrap on: numbers still align with the wrapped lines the same way they
      did before this change (the old gutter drifted here too).

## Published extension index

The app reads
`https://raw.githubusercontent.com/adityagusain273/b-code/main/extensions-index/index.json`,
served from the public `b-code` repository. The source of truth is
`extensions-index/` in this repository; copy it across and push to `main` after
rebuilding the packages. The app repository is private, so it cannot host the
index: unauthenticated raw requests to it return 404.

## Store screenshots

Captured with `tool/capture_screenshots.sh` (see
[`store/screenshots/README.md`](../store/screenshots/README.md)). The script
resolves every tap from the UI hierarchy rather than fixed coordinates, so it
survives a status-bar height or font-scale change; it polls for up to 15 s
instead of sleeping a fixed amount, because a cold start here takes 4 s.

- [x] `01_edit.png` — `showcase.py`, syntax-coloured, gutter numbers, `python`
      and `25 lines` in the status bar. Captured 2026-11-13 on RMX2193.
- [x] `02_run.png` — the same file with the console open, the program's own
      output and `Python 3.14`. Captured 2026-11-13 on RMX2193.
- [ ] `03_github.png` — needs `--dart-define=GITHUB_CLIENT_ID=...`. The script
      SKIPs on a build without one instead of capturing the sign-in screen, so
      the gap is visible rather than silent.

## Known gaps after this pass

- Scrolling a 2001-line file: worst frame is down from 75 ms to 40–52 ms (target
  ≤ 32 ms) after replacing the line-number table with a viewport-only painter.
  The remainder is Flutter painting the whole-file paragraph in `EditableText`,
  which needs a virtualized line renderer to remove. See
  [MANUAL_QA.md](MANUAL_QA.md#scroll-profile-2026-11-13-after-the-gutter-change).
- `03_github.png` is not captured, and the hosted privacy policy is behind the
  local copy until someone with push access to
  `adityagusain273/b-code` publishes it.
