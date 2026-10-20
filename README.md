# B Code

A full-featured code editor for Android — edit, run, and ship code entirely from your phone.
Built with Flutter for a future path to iOS and desktop.

**Package:** `com.bcode.editor` · **Version:** 1.0.0 · **License:** proprietary (TBD)

## Phase 1 feature set

| Area | What ships |
|---|---|
| Editor core | Syntax highlighting (100+ grammars via `highlight`), line numbers, auto-indent, find/replace, multi-tab editing with session restore |
| File explorer | Create / rename / delete / move files & folders, path-escape protection, SAF import/export bridge |
| Extension system | Stable plugin API (`BCodeExtension`, `LanguageContribution`, `RunConfig`) with a central registry; 4 builtin language packs: Python, C, C++, Java |
| Code execution | Local-first runner. Runtimes are installed on demand like a VS Code extension, SHA256-verified, with version and size shown first. Termux is an optional fallback. See [docs/ON_DEVICE_EXECUTION.md](docs/ON_DEVICE_EXECUTION.md). |
| GitHub | OAuth Device Flow login (no secret embedded), repo browser, commit history, clone → edit → pull / commit / push / view diffs via `git2dart` (libgit2) |
| Shared workspace | Optional: `/storage/emulated/0/BCode` so Termux and other apps can edit the same files. Off by default, no permission on first launch, app-private workspace otherwise |
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

- [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) — store-submission placeholder
- [`docs/EXTENSIONS.md`](docs/EXTENSIONS.md) — how to write a language pack
- [`docs/PHASES.md`](docs/PHASES.md) — roadmap and out-of-scope log
