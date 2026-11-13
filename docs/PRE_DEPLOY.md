# Pre-deploy plan — what to close before launch

Companion to [ACODE_COMPARISON.md](ACODE_COMPARISON.md). That document argues
*why* these gaps matter; this one is the execution order, the current state of
each item, and the acceptance test that closes it.

Rules that apply to every task below: no new paid service, no new backend, no
new dependency unless the task cannot be done with what is installed, and
`flutter analyze` + `flutter test` stay clean.

## Status at a glance

| # | Item | Closes | State today |
|---|---|---|---|
| 1 | Extension loop: preview, unload, official index | Ecosystem, distribution | Done — preview, immediate unload, official index published and verified on device |
| 2 | First-run path to a successful Run | Execution promise | Done — onboarding offers Python download with live size/version; editor Run opens download sheet; verified end-to-end on device |
| 3 | Store compliance | Launch | Partial — policy text and data-safety draft exist in `store/`, nothing hosted |
| 4 | Crash and startup budget | Low-end devices | Measured — cold start and PSS pass; 2k-line scroll misses the frame target |
| 5 | Workspace backup/export | Retention | Done — Export project (include/skip .git) round-trips on device |
| 6 | LSP-lite for Python and JS | IDE intelligence | Missing (keyword/symbol completion only) |
| 7 | Git safety: branch, stash, conflicts | Git depth | Partial — clone/commit/push/diff/fast-forward pull |

## 1. Finish the extension loop

**Why it blocks launch.** A user installs a package and sees nothing change
until they open the right file; a user removes one and is told to restart. Both
read as broken. And with no default source, the Community tab is empty on a
fresh install, which looks like the feature does not exist.

**Work.**

1. *Preview before install.* `ExtensionInstaller` already extracts a package
   into a temporary `.incoming-*` directory and validates the manifest before
   moving it into place — today that move happens without asking, and the UI
   activates it immediately afterwards. Split it: `stage` (extract + validate +
   parse, keep the temp directory) and `commit` (move into `rootDir`), then show
   a preview with `displayName`, `version`, `author`, `description`, the
   languages and their file extensions, snippet and theme counts, and the
   README when present, with an explicit **Install** button. Cancel deletes the
   staged copy.
2. *Unload without restart.* `HighlightEngine`, `SnippetService` and
   `SyntaxThemes` only have registration. Add the inverse of each, keyed by
   extension id, and have `ExtensionLoader` record what it registered so removal
   undoes exactly that — never a bundled pack. Bundled languages and themes are
   not installed packages, so removal can only reach the ids it registered.
3. *Official index.* Create the `bcode-extensions` repo with an `index.json`
   and the three or four packages we ship as examples. Add its raw URL as a
   default source in `ExtensionSourceService` (a default, not a hard-coded
   fetch: the user can remove it). Keep the file small enough to stay under the
   existing parse cap.

**Acceptance.**

- Fresh install → Community tab → Get on an example package → preview shows
  exactly what it adds → Install → open a matching file → highlighting applies.
- Remove it → the file loses the grammar and falls back to plain text in the
  same session, with no restart prompt.
- Update path still works against the official index.

## 2. First-run path to a successful Run

**Why it blocks launch.** The product promise is "the editor that runs your
code". If the first Run tap produces a wall of runtime choices, a 40 MB
download with no progress, or a missing download button, the promise is broken
at the first minute.

**Work.**

1. Onboarding ends by creating a runnable file (it already writes a Python
   Hello World) **and** offering "Download Python runtime (≈X MB)" as the final
   step, with size and version shown before the tap.
2. Runtime download must be cancellable, resumable, and honest about progress
   and failures — recheck `RuntimeDownloadService` against a flaky connection
   and a mid-download cancel.
3. If the user skips the download, the Run tap on that file opens the
   runtime download sheet rather than a generic error.

**Acceptance.** Fresh install on a clean device → onboarding → download Python
→ back in the editor → Run → `Hello from B Code!` in the console, with no
Termux installed and no second trip to Settings. *(Verified on device Realme C25
Android 11: both Flow A via onboarding download and Flow B via editor Play button sheet
run and output `Hello from B Code!` in the console panel).*

## 3. Store compliance

**Work.** `store/privacy_policy.html`, `store/data_safety.md` and
`store/listing.md` exist as drafts. What is missing:

- A hosted HTTPS URL for the policy (GitHub Pages from this repo is enough) and
  a support email that someone reads.
- Data-safety answers that match the code: files stay on device, GitHub token
  is stored encrypted, no analytics, no ads, network used only for the user's
  own GitHub and runtime downloads.
- Screenshots that show the three claims in order: edit → run → GitHub.
- The content rating must account for the terminal and GitHub capabilities.
- The 16 KB page-size situation in `store/16kb.md` is launch debt: the first
  internal-testing upload either passes or it does not. Do that upload before
  promising a Play date, and fall back to a GitHub Release APK if it is
  rejected.

**Acceptance.** Internal-testing upload accepted; listing text, policy URL and
support email resolve; every screenshot matches the build being uploaded.

## 4. Crash and startup budget

**Work.**

- Get a 3 GB RAM Android 10–12 device (or constrain the emulator to 3 GB and
  4 cores; it is a proxy, not proof).
- Measure cold start with `adb shell am start -W -n com.bcode.editor/.MainActivity`
  and time-to-first-keystroke by typing immediately after the window appears.
- Build a profile APK and watch `adb logcat` for GC pauses, skipped frames, and
  the first-file load on a 5k-line file.
- Targets: cold start under 3 s, no frame over 32 ms while scrolling a 2k-line
  file, under 250 MB PSS at idle with three tabs open.
- If a target is missed, fix in this order: lazy-load the language grammars,
  move whole-file work off the main isolate, trim the startup work in
  `main.dart` before it renders.

**Acceptance.** Numbers written into `docs/MANUAL_QA.md` with the device model
and build hash, and no new crash cluster in the first week.

## 5. Workspace backup/export

**Work.** One obvious path, not a settings maze: "Export project" in the file
explorer / workspace menu zips the workspace to SAF via the existing
`DeviceImportService.exportFile`, excluding `.git`-heavy paths if the user
chooses. Import already exists ("Unzip Project") — make the pair discoverable
next to each other.

**Acceptance.** Export → uninstall → reinstall → import → every file and
subdirectory intact, including a repo with a `.git` directory, and the editor
opens the restored project without a restart.

## 6. LSP-lite for Python and JavaScript

**Scope.** Three features only: symbol outline, go-to-definition, and inline
diagnostics for the obvious errors. No language server process, no protocol
implementation, no completion rewrite.

**Work.** `lib/lsp/` already holds the completion engine. Add:

- An outline parser per language (indentation blocks for Python, `function`/
  `class`/`const` patterns for JS) feeding a symbol panel or the existing
  symbol index.
- Go-to-definition by resolving the symbol index within the open workspace.
- Diagnostics that are cheap and trustworthy: unbalanced brackets, unterminated
  strings, Python indentation errors, unresolved imports. Anything that needs a
  real parser waits.

**Acceptance.** On a 500-line Python file and a 500-line JS file: outline
matches the file structure, tapping a symbol jumps to the definition, and a
deliberately broken bracket shows one inline diagnostic that clears on fix.

## 7. Git safety

**Work.** `GitService.pull` is fetch + fast-forward, and it refuses to rewind a
branch with unpushed commits — correct, but it reads as broken. Add:

- Branch list, create and switch (with the dirty-tree check the pull path
  already uses).
- Stash: save and restore the working tree.
- A pull that, when fast-forward is impossible, explains the divergence and
  offers merge or rebase instead of a bare refusal.
- Conflict handling can stop at "these files conflict, here is the list, your
  changes are intact" — a conflict editor is not required for launch.

**Acceptance.** On a repo with an upstream change and a local commit: pull
explains the divergence, merge resolves when the files do not overlap, and
stash/restore returns the working tree byte-for-byte.

## Language choice: should any of this be rewritten in Rust?

**Verdict: no. Do not rewrite the app, or any part of it, in Rust for v1.**
The measurements below are from the current release APK, not estimates.

### What the app actually ships

Release APK is 42.3 MB because it carries three ABIs. Native libraries are
36.4 MB of that and are stored uncompressed (required for page alignment).

| Component | Size (arm64 slice) | Already native? |
|---|---|---|
| `libflutter.so` — engine, Skia/Impeller, text shaping, GC | 11.2 MB | Yes, C++ |
| `libapp.so` — Dart AOT snapshot, machine code | 6.9 MB | Yes, compiled |
| libgit2 + libssh2 + OpenSSL (`git2dart_binaries`) | 6.4 MB | Yes, C |
| `classes.dex` — Android/Kotlin glue | 1.0 MB in the APK | — |
| Desktop `zstd-jni` natives (`win/`, `darwin/`) | 1.6 MB in the APK | **Dead weight, never loadable on Android** |

The entire Dart source is 1.1 MB across 114 files. Rewriting all of it would
not move a 24.6 MB arm64 slice; a Rust library would *add* 0.3–1 MB per ABI
plus a cross-compile toolchain, and it would not remove a single byte of the
engine, the AOT snapshot, or the git stack.

### Why speed is not the argument either

- Dart release builds are ahead-of-time compiled to machine code. There is no
  interpreter to delete.
- Text layout, raster, image decode and the GC are inside the engine, already
  native. Rust would replace the glue around them, not the work.
- The felt jank on a 3 GB phone comes from memory and main-isolate work:
  whole-file strings, tokenization on the UI isolate, cold-start work in
  `main.dart`, image decoding. All of those have Dart-side fixes (isolates,
  streaming, lazy loads) that cost days, not quarters.
- Every native library we add inherits the 16 KB page-alignment problem we are
  already carrying for `git2dart_binaries` (`store/16kb.md`). Rust binaries
  would need the same flag and the same CI verification.

### What to do instead (cheap, measured)

1. Exclude the `win/**` and `darwin/**` zstd-jni natives in
   `android/app/build.gradle.kts`. They are plain Java resources inside the
   `zstd-jni` jar, not `jniLibs`, so use `packagingOptions.resources.excludes`
   (or `ignoreAssetsPattern`), not `jniLibs.excludes` — the latter will not
   match them. Measured: 1.6 MB in the current APK.
2. Produce per-ABI APKs (`--split-per-abi`) for direct distribution so an
   arm64 phone downloads ~24 MB, not 42 MB. Play already splits the bundle;
   verify the delivered size from the internal-testing track.
3. Re-run the startup/memory measurements in item 4 before optimizing anything.
4. Revisit native code only when a profile shows a specific hotspot that
   isolates cannot fix, and only for that function — full-text search over very
   large trees, diff/merge, or tree-sitter parsing for real LSP later. Tree-
   sitter is C, not Rust; the language matters less than the measured win.

### Rule for future sessions

Do not rewrite working Dart in Rust, C or C++ to "make it fast" or "make it
small". Ship the measurement first. The only native code we own should be code
a profiler demanded.

## Suggested order

1 → 5 → 4 → 2 → 3 → 7 → 6. The extension loop and backup are small and stop
review damage; the startup numbers decide whether anything else needs to move;
first-run and store work gate the upload; git and LSP-lite are the visible
Acode gaps and can follow the internal-testing build.

## Next-session prompt

```text
Continue the pre-deploy work on B Code, a Flutter Android code editor in
/home/advaiti/Desktop/b_code (package com.bcode.editor, Flutter 3.47.1 stable,
Dart 3.13.1).

Read first: AGENTS.md, docs/PRE_DEPLOY.md (status table, sections 1, 4 and 5),
docs/EXTENSIONS.md, docs/ACODE_COMPARISON.md. The working tree already contains
uncommitted extension-package work (lib/plugins/packages/, the extensions page,
tests). Build on it; do not revert or rewrite it.

Session goal, in this order: finish the extension loop, add workspace export,
then measure startup and memory. Nothing else.

Constraints:
- Zero cost. No paid service, no backend, no marketplace, no new dependency
  unless the task is impossible without one.
- Match the existing style. No comments unless they explain a non-obvious why.
- Do not rewrite Dart in Rust/C/C++. Performance work waits for a profile.
- Do not run device UI tests. Build, install, and describe what the user should
  test by hand.
- Builds are offline-cached: never run flutter upgrade/channel, sdkmanager, or
  flutter clean. Prefer CI (push -> GitHub Actions) for release builds; use
  tool/dev.sh only for hot-reload iteration.
- Finish with `flutter analyze` (0 issues) and `flutter test` (all pass).

Task 1 - extension loop (PRE_DEPLOY.md section 1)
a. Split ExtensionInstaller.installArchive / installUrl / installDirectory into
   stage (extract into .incoming-*, validate the manifest, parse, keep it) and
   commit (move into rootDir). Show a preview dialog before commit:
   displayName, version, author, description, every language with its file
   extensions, snippet and theme counts, and the README when present. Cancel
   deletes the staged copy. A failed commit leaves no half-installed directory.
b. Add unregistration to HighlightEngine, SnippetService and SyntaxThemes,
   keyed by extension id. Have ExtensionLoader record exactly what each package
   registered so removal undoes only that and never a bundled pack. Drop the
   "restart to unload" snackbar once removal takes effect immediately.
c. Add the official static index as a default source: create
   extensions-index/index.json in this repo (publishable on GitHub Pages) with
   the example packages, and register its URL in ExtensionSourceService as a
   removable default. It must appear exactly once on a fresh install.
d. Tests: stage -> preview -> cancel leaves nothing installed; install -> remove
   reverts the grammar in the same session; a package cannot override a bundled
   language; the default source appears exactly once.

Task 2 - workspace export (PRE_DEPLOY.md section 5)
Add "Export project" beside the existing "Unzip Project" flow. Zip the workspace
with the ZipEncoder already used by ExtensionInstaller, write through
DeviceImportService.exportFile (SAF), and keep the import/export pair
discoverable in the same place. Test the archive builder with a nested
directory, an empty directory, and a file above 1 MB.

Task 3 - measurements, report only (PRE_DEPLOY.md section 4)
If a device or emulator is already running: cold start with
`adb shell am start -W -n com.bcode.editor/.MainActivity`, idle PSS with three
tabs open, and worst frame while scrolling a 2000-line file in a profile build.
Write the device model, build hash and numbers into docs/MANUAL_QA.md. If
nothing is running, say so and skip; do not start an emulator unless asked.

Also confirm from android/app/build.gradle.kts whether the win/** and darwin/**
zstd-jni resources are still packaged. If they are, add
packagingOptions.resources.excludes for them (they are jar resources, not
jniLibs) and report the APK size before and after.

Do not touch: the first-run runtime download flow, store listing, LSP-lite, or
git branch/stash/conflict work. Those are later sessions.

Report back with: files changed, what the tests prove, the analyze and test
output, any APK size delta, and the manual steps the user should try on device.
```
