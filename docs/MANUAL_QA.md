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

## 8. Stability sweep (10 min, no interaction)
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

## Manual checks for the extension and export work

- [ ] Fresh install → Extensions → Community → the four official packages
      appear (Rust, Go, Kotlin, Rails). The official source is present once
      under Sources and can be removed.
- [ ] Get on Rust → preview shows version, author, language `.rs`, snippet and
      theme counts, and the README → Cancel leaves nothing installed (no
      `com.bcode.extension.rust` folder, no `.incoming-*`).
- [ ] Install Rust → open a `.rs` file → highlighting applies without reopening
      the app. Remove it → the same open file falls back to plain text
      immediately; no restart snackbar.
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

## Known gaps after this pass

- The Community tab shows "1 source(s) could not be loaded" until
  `extensions-index/` is pushed to `adityagusain273/b-code-app:master`, so the
  raw index URL resolves. The folder is committed locally and the four packages
  are built, but GitHub raw is still serving a 404 for it.
- Scrolling a 2001-line file misses the 32 ms frame target on a 3 GB device.
  No profile has been taken yet, so no fix is proposed.
