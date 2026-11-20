# Kriya (Kriya Code)

A full-featured code editor for Android — edit, run, and ship code entirely from your phone.
Built with Flutter for a future path to iOS and desktop.

**Package:** `com.kriya.editor` · **Version:** 1.0.0 · **License:** proprietary (TBD)

## Phase 1 feature set

| Area | What ships |
|---|---|
| Editor core | Syntax highlighting (100+ grammars via `highlight`), line numbers, auto-indent, find/replace, multi-tab editing with session restore |
| File explorer | Create / rename / delete / move files & folders, path-escape protection, SAF import/export bridge |
| Extension system | Stable extension API with a central registry; 10 builtin language packs: Python, C, C++, Java, JavaScript, TypeScript, HTML, CSS, JSON, Markdown. Installable `.bcext` packages add languages, snippets and themes from a file, URL or static index — no code execution |
| Code execution | Local-first runner. Runtimes are installed on demand like a VS Code extension, SHA256-verified, with version and size shown first. Termux is an optional fallback. See [docs/ON_DEVICE_EXECUTION.md](docs/ON_DEVICE_EXECUTION.md). |
| GitHub | OAuth Device Flow login (no secret embedded), repo browser, commit history, clone → edit → pull / commit / push / view diffs via `git2dart` (libgit2) |
| Shared workspace | Optional: `/storage/emulated/0/Kriya` so Termux and other apps can edit the same files. Off by default, no permission on first launch, app-private workspace otherwise |
| Deploy-readiness | Release signing config (`android/key.properties.example`), minSdk 24, targetSdk 36, store-compliant, execution via the system linker, privacy policy placeholder, monetization seam (`EntitlementService`) with no paid SDKs |

## Architecture

```
lib/
├── main.dart            bootstrap + DI registration
├── app.dart             MaterialApp shell
├── core/                Result<T>, ServiceLocator, constants
├── editor/              tabs, find/replace, highlighting service
├── workspace/           FsService (sandboxed root) + explorer UI
├── plugins/
│   ├── api/             public extension interfaces
│   ├── host/            registries + event bus
│   └── builtin/         python / c / cpp / java packs
├── execution/           RunnerService facade, runtime downloads, local bridge, console UI
├── github/              device-flow auth, REST client, git2dart ops, UI
├── settings/            persisted prefs + page
└── monetization/        EntitlementService interface + free stub
```

Native side (Android host, Kotlin): `ExecPlugin` spawns local runtime processes;
`MainActivity` wires it plus the SAF import/export channel. See
`android/app/src/main/kotlin/com/bcode/editor/`.

## Building & running

```bash
flutter pub get
flutter run                # debug on device/emulator
flutter test               # unit tests
flutter analyze            # static analysis (currently clean)
```

### GitHub client ID

The Device Flow needs an OAuth App client ID (register one at
<https://github.com/settings/developers> — enable *Device Flow*, no callback URL needed):

```bash
flutter run --dart-define=GITHUB_CLIENT_ID=your_client_id
```

### Release build

1. Generate a keystore and copy `android/key.properties.example` → `android/key.properties`.
2. `flutter build appbundle` (Play Store) or `flutter build apk --release`.

## Local runtimes (Phase 2 activation)

Execution architecture relies on local binaries: `LocalRunner` talks to `ExecPlugin` or `TermuxPlugin` to execute language runtimes natively on the device. For Android 10+ (API 29+), dynamic binary execution uses packaged native libraries in the APK to comply with W^X enforcement.

## Docs

- [`docs/privacy-policy.html`](docs/privacy-policy.html) — Store privacy policy
- [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) — store-submission placeholder
- [`docs/EXTENSIONS.md`](docs/EXTENSIONS.md) — extension package format, creation and publishing
- [`docs/ACODE_COMPARISON.md`](docs/ACODE_COMPARISON.md) — competitor comparison and post-launch roadmap
- [`docs/PRE_DEPLOY.md`](docs/PRE_DEPLOY.md) — launch blockers, ordered work and the performance decision
- [`docs/PHASES.md`](docs/PHASES.md) — roadmap and out-of-scope log

## Legal Disclaimer

Kriya is an independent software application developed for mobile devices. It is not affiliated with, sponsored by, or endorsed by Microsoft Corporation.

