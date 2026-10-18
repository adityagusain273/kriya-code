# B Code Extension API (v1)

B Code's language support is pluggable from day one. A language pack is a Dart class
implementing `BCodeExtension` that contributes a `LanguageContribution` to the registry
when activated. Nothing in the editor core knows about specific languages.

> **Why statically registered?** Dart AOT compilation cannot load dynamic code at
> runtime, so v1 extensions ship inside the app but behind stable interfaces. The v2
> plan adds a WASM/JS sandbox for true third-party dynamic plugins using the same
> contribution shape — see `docs/PHASES.md`.

## Minimal language pack

```dart
import 'package:highlight/languages/rust.dart';

import '../../api/extension.dart';
import '../../api/language_contribution.dart';
import '../../api/run_config.dart';

class RustExtension extends BCodeExtension {
  static final LanguageContribution _contribution = LanguageContribution(
    id: 'rust',
    name: 'Rust',
    fileExtensions: ['rs'],
    grammar: rust,                       // highlight-package Mode
    indentRules: const IndentRules(
      indentWidth: 4,
      blockOpeners: ['{'],
      blockClosers: ['}'],
    ),
    runConfig: const RunConfig(
      local: LocalTarget(
        runtimeId: 'rust',
        runArgv: ['{runtimePath}/bin/rustc', '{file}'],
      ),
    ),
  );

  @override
  String get id => 'bcode.lang.rust';
  @override
  String get name => 'Rust Language Pack';
  @override
  String get version => '1.0.0';

  @override
  Future<void> activate(ExtensionContext context) async {
    context.languages.register(_contribution);
    // Optional: context.commands.register('bcode.rust.fmt', ...);
  }

  @override
  Future<void> deactivate() async {}
}
```

Register it in `lib/plugins/builtin/builtin_extensions.dart`. That is the only core edit
required — highlighting, tab management, and the runner pick it up automatically.

## Run configuration semantics

`RunConfig` drives the execution facade (`execution/runner_service.dart`):

`RunConfig` drives the execution facade (`execution/runner_service.dart`):

- **`LocalTarget.runtimeId`** — the ID of the local runtime.
- **`LocalTarget.buildArgv` / `runArgv`** — argv templates with substitution tokens:
  - `{runtimeDir}` — absolute path of the root runtimes directory
  - `{runtimePath}` — absolute path to this specific runtime
  - `{file}` — absolute path of the file being run
  - `{dir}` / `{name}` — its parent directory and basename-without-extension

## Available context services

| `ExtensionContext` member | Purpose |
|---|---|
| `languages` | Register `LanguageContribution`s |
| `commands` | Register named commands callable from UI |
| `events` | Subscribe to document opened/saved/closed events |
| `fs` | Sandboxed workspace file access |

## Rules for extension authors

1. Never block `activate()` — do heavy work lazily.
2. All paths must go through `FsService`; direct `dart:io` access outside the workspace
   root will be rejected.
3. Extensions are trusted first-party code in v1; a permission model lands together with
   dynamic loading in v2.
