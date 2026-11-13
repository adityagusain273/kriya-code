# B Code Roadmap

## Phase 1 — shipped scope (this codebase)

- [x] Editor core: highlighting, line numbers, auto-indent (via `flutter_code_editor`)
- [x] Multi-tab editing with session restore
- [x] Find / replace bar
- [x] File explorer: create, rename, delete, move; SAF import/export bridge on Android
- [x] Extension system v1: static registry + stable interfaces, event bus, command registry
- [x] Installable `.bcext` packages: languages, snippets, themes; install from file,
      HTTPS URL or a static index; public/private distribution with no server
- [x] Language packs: Python, C, C++, Java (grammar + run config each)
- [x] Execution facade: local runtimes via bundled Termux packages
- [x] Local exec bridge (`ExecPlugin`) ready for bundled runtimes
- [x] GitHub: Device Flow login, repo browser, commit history, clone/pull/commit/push/diff
- [x] Deploy-readiness: `com.bcode.editor`, signing config, minSdk 24, INTERNET-only,
      privacy policy placeholder, monetization seam without paid SDKs

## Phase 2 — local runtimes & store launch

Execution order and acceptance tests for this phase: [PRE_DEPLOY.md](PRE_DEPLOY.md).

- [ ] Finish the extension loop: install preview, unload without restart, official index
- [ ] First-run path that ends in a working Run
- [ ] Workspace export (zip) before users lose projects on uninstall
- [ ] Measure cold start and idle memory on a 3 GB device
- [ ] LSP-lite (outline, go-to-definition, diagnostics) for Python and JS
- [ ] Git branch switch, stash, and a pull that explains conflicts
- [ ] Ship CPython + clang as Play Feature Delivery modules into `<filesDir>/runtimes/`
- [ ] First-run runtime download UX (Play Feature Delivery triggers)
- [ ] App icon final art + adaptive icons + splash
- [ ] Real privacy policy URL + support email + store listing copy
- [ ] Integration tests on device/emulator matrix
- [ ] Play Store submission

## Phase 3 — editor power features

- [ ] Code folding UI polish, breadcrumbs, go-to-file palette
- [ ] LSP-lite: symbol outline for the 4 languages
- [ ] Snippets per language pack
- [ ] Themes (bundled set) — marketplace deferred to Phase 5

## Phase 4 — collaboration groundwork

- [ ] Gist create/read from GitHub module
- [ ] Live collaboration (CRDT) evaluation

## Phase 5 — expansion

- [ ] Dynamic extension loading (WASM/JS sandbox) reusing v1 contribution shape
- [ ] Theme marketplace
- [ ] Additional language packs beyond the launch 4
- [ ] Integrated terminal beyond basic run/output console
- [ ] iOS build (cloud-execution only — Apple policy forbids on-device compilation of
      downloaded code)
- [ ] Desktop builds (Windows/macOS/Linux) via existing Flutter targets

## Explicitly out of scope in Phase 1 (per product decision)

- Themes marketplace · live collaboration · full terminal · >4 languages · iOS build
