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
