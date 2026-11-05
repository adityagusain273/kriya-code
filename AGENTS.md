# AGENTS.md — b_code (mobile code editor)
B code is an mobile based code editor app supporting all languages and perfoming web dev too. 
Guidance for AI coding agents working in this repository. Read this fully before running any commands.

## Project

Flutter app (Dart 3.13.1, Flutter 3.47.1 stable) — a VS Code-like code editor for Android.
- App package: `com.bcode.editor` (`android/app/src/main/kotlin/com/bcode/editor/MainActivity.kt`)
- Key areas: `lib/workspace/` (file explorer + FsService), `lib/plugins/` (extensions system), `lib/execution/` (runtime downloads), `lib/editor/` (editor page/home)

## One-time environment — ALREADY INSTALLED, NEVER RE-DOWNLOAD

Everything below is fully set up and cached (~19 GB total). All builds and installs work 100% offline.

| Component | Version | Location | Size |
|---|---|---|---|
| Flutter SDK | 3.47.1 stable (Dart 3.13.1) | `~/development/flutter` | 2.3 GB |
| Android SDK | platform-tools, build-tools, platforms, NDK, cmake, emulator, system-images | `~/Android/Sdk` | 7.3 GB |
| Java | OpenJDK 17 (system) | system install | — |
| Gradle | 9.3.1 + all dependency artifacts | `~/.gradle` | 5.9 GB |
| Pub packages | all deps cached (provider, http, git2dart, flutter_code_editor, …) | `~/.pub-cache` | 690 MB |
| Emulator AVD | `bcode_test` (appears as `emulator-5554`) | `~/.android/avd/bcode_test.avd` | 3.1 GB |
| Debug APK | last successful build | `build/app/outputs/flutter-apk/app-debug.apk` | ~175 MB |

The user pays for mobile data. Builds and installs consume ZERO internet because:
- `flutter pub get` resolves from `~/.pub-cache`
- Gradle resolves from `~/.gradle` (dist already unpacked)
- `adb install` pushes over local ADB (localhost), not the network

## Standard update loop (after ANY code change)

One command does build + install + launch, and verifies the app reached the
foreground before reporting success:

```bash
tool/dev.sh
```

```bash
tool/dev.sh test     # flutter analyze + full test suite
tool/dev.sh run      # flutter run, for hot reload (press r)
tool/dev.sh release  # release APK; refuses to build without GITHUB_CLIENT_ID
```

It polls the window focus for up to 80s after launching: a cold start on a slow
device can take half a minute, and a fixed short wait reports a working build as
broken.

`GITHUB_CLIENT_ID` is optional. A debug build with no `--dart-define` starts and runs
normally; only GitHub sign-in reports itself unavailable, and release builds still
refuse to start without a real client id so a misconfigured release cannot ship.
Export `GITHUB_CLIENT_ID` to exercise sign-in.

The user tests manually. Do not run UI tests yourself; just build, install, and
describe what to test.

## Offline engine mirror

The `io.flutter:<abi>_debug` jars are published only to storage.googleapis.com. Where
that host is unreachable and those jars are not in the Gradle cache, **every Android
build hangs part-way through dependency resolution** instead of failing fast — no
error, just no output.

If a build hangs after the Gradle/Kotlin warning banner, run:

```bash
tool/make-local-engine-repo.sh    # ~20s, writes android/local-engine-repo/
```

It assembles the same Maven coordinates from jars already inside the Flutter SDK. The
per-ABI artifacts are repacked as thin jars (one `libflutter.so`, no classes) because
the SDK's `flutter.jar` is the fat embedding jar and four copies of it fail the
duplicate-class check.

`android/build.gradle.kts` adds the mirror **only when the directory exists**, so on a
normal machine and in CI it is skipped and the published repository is used. The
directory is gitignored — roughly 1 GB of machine-specific binaries.

## Emulator

```bash
# Start (background, takes ~30-60s to boot):
nohup ~/Android/Sdk/emulator/emulator -avd bcode_test -netdelay none -netspeed full \
  > /tmp/opencode/emulator.log 2>&1 &

# Wait for boot (repeat until it prints 1):
adb shell getprop sys.boot_completed
```

- The emulator persists installed apps and app data between sessions — reinstall the APK only after a code change.
- NEVER launch with `-wipe-data` (destroys the user's workspace files stored in app storage).
- If `adb devices` shows `emulator-5554  device`, an emulator is already running — do not start another.

## Hot reload (fastest iteration, no reinstall)

```bash
flutter run -d emulator-5554
```
Press `r` in that session after each code change. Use the build+install loop above instead when no interactive session is running.

## FORBIDDEN (each of these wastes the user's internet or data)

- `flutter upgrade` / `flutter channel` / `flutter downgrade`
- `sdkmanager --install` or re-accepting licenses
- Deleting or cleaning `~/.gradle`, `~/.pub-cache`, `~/Android/Sdk`
- `flutter clean` (only if the build is genuinely corrupted)
- `flutter create` or regenerating the `android/` folder
- `-wipe-data` on the emulator

If dependencies appear broken, try offline resolution first: `flutter pub get --offline`, then `./android/gradlew --offline` from `android/`.

- No code comments unless asked; match existing style (no comments in current codebase).
- Run `flutter analyze` after changes; it must report 0 issues.

## Cloud-First Builds (for RAM-limited laptop)
The laptop has 14 GiB RAM (shared with AMD Radeon iGPU). Running Gradle locally alongside an IDE risks OOM crashes.

**Preferred build path — use GitHub Actions cloud runners:**
1. Push code to `master` → GitHub Actions auto-triggers `.github/workflows/build-apk.yml`
2. Or go to GitHub → Actions → "Build Android APK" → Run workflow (choose debug or release)
3. Download `b-code-debug-apk` artifact from GitHub

Only use `tool/dev.sh` locally when you need hot-reload iteration on the emulator. Never run a full `flutter build apk --release` locally unless specifically requested.

## Bootstrapping Rules
- Use free public APIs (public-apis/public-apis, GitHub public API, etc.) for testing and initial production.
- Do not introduce paid API services when a free alternative exists.
- Wrap all third-party clients behind service interfaces with keys in env vars for easy future swap.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
