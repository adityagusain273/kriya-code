import 'package:b_code/execution/runtime_catalog.dart';
import 'package:b_code/plugins/api/extension.dart';
import 'package:b_code/plugins/api/language_contribution.dart';
import 'package:b_code/plugins/builtin/builtin_extensions.dart';
import 'package:b_code/plugins/host/command_registry.dart';
import 'package:b_code/plugins/host/event_bus.dart';
import 'package:b_code/plugins/host/language_registry.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Placeholders `LocalRunner` knows how to substitute.
///
/// Anything else in a template is handed to the process verbatim, which is how a
/// broken command survives review and then fails on a user's phone with an
/// unhelpful "No such file or directory".
const supportedTokens = {
  '{runtimeDir}',
  '{runtimePath}',
  '{file}',
  '{dir}',
  '{outDir}',
  '{name}',
};

/// Shell metacharacters. Nothing runs through a shell, so these are never operators
/// here — they are stray characters in an argument list.
const shellOperators = {'&&', '||', ';', '|', '>', '<', '`', r'$(', '&'};

/// Minimal context so the builtin extensions can register their languages without
/// pulling in the whole app bootstrap.
class _CaptureContext implements ExtensionContext {
  @override
  final LanguageRegistry languages;
  @override
  final CommandRegistry commands = CommandRegistry();
  @override
  final BCodeEventBus events = BCodeEventBus();
  @override
  final FsService fs;

  _CaptureContext(this.languages, this.fs);
}

Future<List<LanguageContribution>> _builtinLanguages() async {
  final registry = LanguageRegistry();
  final context = _CaptureContext(registry, FsService('/tmp'));
  for (final extension in builtinExtensions) {
    await extension.activate(context);
  }
  return registry.all;
}

void main() {
  late List<LanguageContribution> languages;

  setUpAll(() async {
    languages = await _builtinLanguages();
  });

  test('the builtin extensions contribute languages', () {
    expect(languages, isNotEmpty);
  });

  group('run configs are executable as written', () {
    test('every template uses only known placeholders', () {
      for (final language in languages) {
        final config = language.runConfig;
        if (!config.hasLocal) continue;
        final local = config.local!;
        for (final arg in [...?local.buildArgv, ...local.runArgv]) {
          for (final match
              in RegExp(r'\{[a-zA-Z_][a-zA-Z0-9_]*\}').allMatches(arg)) {
            expect(
              supportedTokens,
              contains(match.group(0)),
              reason:
                  '${language.id}: unsupported placeholder ${match.group(0)} in '
                  '"$arg". It would reach the process verbatim.',
            );
          }
        }
      }
    });

    test('no run config smuggles in a shell operator', () {
      for (final language in languages) {
        final config = language.runConfig;
        if (!config.hasLocal) continue;
        final local = config.local!;
        for (final arg in [...?local.buildArgv, ...local.runArgv]) {
          expect(
            shellOperators,
            isNot(contains(arg)),
            reason:
                '${language.id}: "$arg" is a shell operator, but the runner spawns '
                'the process directly and never uses a shell. Split the work into '
                'buildArgv and runArgv.',
          );
        }
      }
    });

    test('compiled output lands app-private, never in the workspace', () {
      for (final language in languages) {
        final config = language.runConfig;
        if (!config.hasLocal) continue;
        final build = config.local!.buildArgv;
        if (build == null || build.isEmpty) continue;

        // `{dir}` is the folder holding the source. With the shared workspace
        // enabled that folder is on the `noexec` volume, where a freshly built
        // binary cannot be started at all.
        expect(
          build.any((arg) => arg.contains('{dir}') && arg.contains('.out')),
          isFalse,
          reason:
              '${language.id}: compiles into the workspace. Use {outDir} so the '
              'binary is built where it can be executed.',
        );
      }
    });

    test('every referenced runtime is installable', () {
      for (final language in languages) {
        final config = language.runConfig;
        if (!config.hasLocal) continue;
        expect(
          runtimeCatalog,
          contains(config.local!.runtimeId),
          reason:
              '${language.id} wants runtime "${config.local!.runtimeId}", which is '
              'not in the catalogue, so it could never be installed.',
        );
      }
    });

    test('a language with a build step also has something to run', () {
      for (final language in languages) {
        final config = language.runConfig;
        if (!config.hasLocal) continue;
        if ((config.local!.buildArgv ?? const []).isEmpty) continue;
        expect(
          config.local!.runArgv,
          isNotEmpty,
          reason: '${language.id} compiles but never runs the result',
        );
      }
    });
  });

  group('runtime catalogue', () {
    test('every runtime has a valid id, packages and an extension', () {
      for (final entry in runtimeCatalog.entries) {
        expect(entry.key, matches(RegExp(r'^[a-z0-9][a-z0-9._-]{0,31}$')));
        expect(entry.value.packages, isNotEmpty);
        for (final id in entry.value.extensionIds) {
          expect(id, startsWith('bcode.lang.'));
        }
      }
    });

    test('each runtime maps only to languages that exist', () {
      final ids = languages.map((l) => l.id).toSet();
      for (final entry in runtimeCatalog.entries) {
        for (final id in entry.value.extensionIds) {
          expect(
            id,
            startsWith('bcode.lang.'),
            reason: '$id is not a language pack',
          );
          expect(
            ids,
            contains(id.substring('bcode.lang.'.length)),
            reason: '$id has no builtin language pack, so installing the runtime '
                'would not make the language usable',
          );
        }
      }
    });

    test('the C/C++ runtime enables both of its languages', () {
      // One runtime, two languages: getting this wrong leaves C++ users unable to
      // run code after installing the toolchain.
      expect(
        runtimeCatalog['clang']!.extensionIds,
        containsAll(['bcode.lang.c', 'bcode.lang.cpp']),
      );
    });
  });
}