import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:kriya_code/editor/highlighting/highlight_engine.dart';
import 'package:kriya_code/editor/highlighting/syntax_themes.dart';
import 'package:kriya_code/editor/snippets.dart';
import 'package:kriya_code/plugins/packages/extension_installer.dart';
import 'package:kriya_code/plugins/packages/extension_loader.dart';
import 'package:kriya_code/plugins/packages/extension_manifest.dart';
import 'package:kriya_code/plugins/packages/extension_scaffold.dart';
import 'package:kriya_code/plugins/packages/extension_source.dart';
import 'package:kriya_code/workspace/fs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

String _manifest({
  String id = 'com.example.rust',
  Object? language,
  Object? themes,
  Object? snippets,
}) =>
    jsonEncode({
      'manifestVersion': 1,
      'id': id,
      'name': 'Rust',
      'version': '1.0.0',
      'description': 'Rust highlighting',
      'author': 'Example',
      'contributes': {
        'languages': [
          language ??
              {
                'id': 'rust',
                'name': 'Rust',
                'extensions': ['rs'],
                'grammar': 'rust',
                'indentWidth': 4,
              }
        ],
        if (snippets != null) 'snippets': snippets,
        if (themes != null) 'themes': themes,
      },
    });

void main() {
  group('ExtensionManifest', () {
    test('parses languages, snippets and themes', () {
      final manifest = ExtensionManifest.parse(_manifest(
        snippets: {
          'rust': {
            'fn': {
              'label': 'Function',
              'body': ['fn name() {', '\t\$0', '}'],
            }
          }
        },
        themes: [
          {
            'id': 'rust-dark',
            'name': 'Rust Dark',
            'colors': {
              'background': '#101010',
              'foreground': '#eeeeee',
              'keyword': '#ff0000',
            },
          }
        ],
      ));

      expect(manifest.id, 'com.example.rust');
      expect(manifest.languages.single.grammar, 'rust');
      expect(manifest.snippets['rust']!.single.body, contains('\$0'));
      expect(manifest.themes.single.colors['background'], '#101010');
    });

    test('rejects reserved and malformed ids', () {
      expect(
        () => ExtensionManifest.parse(_manifest(id: 'bcode.lang.rust')),
        throwsA(isA<ExtensionFormatException>()),
      );
      expect(
        () => ExtensionManifest.parse(_manifest(id: '../escape')),
        throwsA(isA<ExtensionFormatException>()),
      );
    });

    test('rejects unknown grammars and bundled languages', () {
      expect(
        () => ExtensionManifest.parse(_manifest(
          language: {
            'id': 'rust',
            'name': 'Rust',
            'extensions': ['rs'],
            'grammar': 'not-a-real-grammar',
          },
        )),
        throwsA(isA<ExtensionFormatException>()),
      );
      expect(
        () => ExtensionManifest.parse(_manifest(
          language: {
            'id': 'python',
            'name': 'Python',
            'extensions': ['rs'],
            'grammar': 'rust',
          },
        )),
        throwsA(isA<ExtensionFormatException>()),
      );
      expect(
        () => ExtensionManifest.parse(_manifest(
          language: {
            'id': 'rust',
            'name': 'Rust',
            'extensions': ['py'],
            'grammar': 'rust',
          },
        )),
        throwsA(isA<ExtensionFormatException>()),
      );
    });

    test('requires a real theme background and foreground', () {
      expect(
        () => ExtensionManifest.parse(_manifest(themes: [
          {
            'id': 'broken',
            'name': 'Broken',
            'colors': {'keyword': '#ff0000'},
          }
        ])),
        throwsA(isA<ExtensionFormatException>()),
      );
    });
  });

  group('ExtensionInstaller', () {
    late Directory temp;
    late Directory root;
    late ExtensionInstaller installer;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bcode_ext_test');
      root = Directory(p.join(temp.path, 'installed'))..createSync();
      installer = ExtensionInstaller(rootDir: root.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('installs a zip and replaces it on upgrade', () async {
      final archive = File(p.join(temp.path, 'rust.bcext'));
      await archive.writeAsBytes(_zip({
        'extension.json': _manifest(),
        'snippets/rust.json': '{}',
      }));

      final first = await installer.installArchive(archive);
      expect(first.manifest.id, 'com.example.rust');
      expect(await Directory(first.directory).exists(), isTrue);
      expect((await installer.installed()).length, 1);

      await archive.writeAsBytes(_zip({
        'extension.json': _manifest(id: 'com.example.rust'),
        'extra.txt': 'updated',
      }));
      await installer.installArchive(archive);
      expect(await installer.installed(), hasLength(1));

      await installer.uninstall('com.example.rust');
      expect(await installer.installed(), isEmpty);
    });

    test('accepts a package wrapped in one top-level folder', () async {
      final archive = File(p.join(temp.path, 'wrapped.bcext'));
      await archive.writeAsBytes(_zip({
        'rust-extension/extension.json': _manifest(),
      }));

      final installed = await installer.installArchive(archive);
      expect(installed.manifest.id, 'com.example.rust');
    });

    test('refuses a zip-slip entry', () async {
      final archive = File(p.join(temp.path, 'evil.bcext'));
      await archive.writeAsBytes(_zip({
        'extension.json': _manifest(),
        '../escaped.txt': 'nope',
      }));

      expect(
        () => installer.installArchive(archive),
        throwsA(isA<Exception>()),
      );
      expect(File(p.join(temp.path, 'escaped.txt')).existsSync(), isFalse);
    });

    test('downloads and installs from https', () async {
      final bytes = _zip({'extension.json': _manifest()});
      final client = MockClient((request) async {
        expect(request.url.scheme, 'https');
        return http.Response.bytes(bytes, 200);
      });
      final downloader = ExtensionInstaller(rootDir: root.path, client: client);

      final installed =
          await downloader.installUrl('https://example.com/rust.bcext');
      expect(installed.manifest.name, 'Rust');
    });

    test('installs a folder for the edit-and-reload loop', () async {
      final source = Directory(p.join(temp.path, 'source'))..createSync();
      File(p.join(source.path, 'extension.json'))
          .writeAsStringSync(_manifest());

      final installed = await installer.installDirectory(source.path);
      expect(installed.manifest.id, 'com.example.rust');
      expect((await installer.installed()).single.manifest.name, 'Rust');
    });

    test('scaffold produces a valid, installable manifest', () async {
      final fs = FsService(temp.path);
      final root = await ExtensionScaffold.create(fs);
      final manifest =
          ExtensionManifest.parse(await fs.readFile('$root/extension.json'));
      expect(manifest.id, 'com.example.hello-bcode');
      expect(manifest.languages.single.grammar, 'ini');
    });

    test('packages a folder into a .bcext that installs again', () async {
      final source = Directory(p.join(temp.path, 'source'))..createSync();
      File(p.join(source.path, 'extension.json'))
          .writeAsStringSync(_manifest());
      final output = p.join(temp.path, 'rust-1.0.0.bcext');

      final name = await installer.packageDirectory(source.path, output);
      expect(name, 'com.example.rust-1.0.0.bcext');
      expect(File(output).existsSync(), isTrue);

      final secondRoot = Directory(p.join(temp.path, 'second'))..createSync();
      final second = ExtensionInstaller(rootDir: secondRoot.path);
      final installed = await second.installArchive(File(output));
      expect(installed.manifest.id, 'com.example.rust');
    });

    test('staging reads the preview without installing, cancel leaves nothing',
        () async {
      final archive = File(p.join(temp.path, 'preview.bcext'));
      await archive.writeAsBytes(_zip({
        'extension.json': _manifest(
          snippets: {
            'rust': {
              'fn': {'body': 'fn main() {}'}
            }
          },
        ),
        'README.md': '# Rust\n\nHighlighting and a function snippet.',
      }));

      final staged = await installer.stageArchive(archive);

      expect(staged.manifest.name, 'Rust');
      expect(staged.readme, contains('function snippet'));
      expect(staged.snippetCount, 1);
      expect(staged.manifest.languages.single.extensions, ['rs']);
      expect(await installer.installed(), isEmpty);
      expect(
        Directory(root.path)
            .listSync()
            .whereType<Directory>()
            .where((dir) => p.basename(dir.path).startsWith('.incoming-')),
        hasLength(1),
      );

      await installer.discard(staged);

      expect(await installer.installed(), isEmpty);
      expect(File(p.join(root.path, staged.manifest.id)).existsSync(), isFalse);
      expect(
        Directory(root.path)
            .listSync()
            .where((entity) => p.basename(entity.path).startsWith('.')),
        isEmpty,
      );
    });

    test('a staged package is only moved into place on commit', () async {
      final archive = File(p.join(temp.path, 'commit.bcext'));
      await archive.writeAsBytes(_zip({'extension.json': _manifest()}));

      final staged = await installer.stageArchive(archive);
      final installed = await installer.commit(staged);

      expect(installed.manifest.id, 'com.example.rust');
      expect((await installer.installed()).single.manifest.id,
          'com.example.rust');
      expect(
        Directory(root.path)
            .listSync()
            .where((entity) => p.basename(entity.path).startsWith('.')),
        isEmpty,
      );
    });

    test('a failed commit leaves the old install intact', () async {
      final good = File(p.join(temp.path, 'good.bcext'));
      final bad = File(p.join(temp.path, 'bad.bcext'));
      await good.writeAsBytes(_zip({'extension.json': _manifest()}));
      await bad.writeAsBytes(_zip({'extension.json': _manifest()}));

      await installer.installArchive(good);
      final staged = await installer.stageArchive(bad);
      final tampered = StagedExtension(
        manifest: staged.manifest,
        directory: p.join(temp.path, 'missing-package-root'),
        container: staged.container,
      );

      await expectLater(installer.commit(tampered), throwsA(isA<Exception>()));

      expect(await installer.installed(), hasLength(1));
      expect((await installer.installed()).single.directory,
          p.join(root.path, 'com.example.rust'));
      expect(
        Directory(root.path)
            .listSync()
            .where((entity) => p.basename(entity.path).startsWith('.')),
        isEmpty,
      );
    });
  });

  group('activation', () {
    test('registers language, snippet and theme without overriding built-ins',
        () {
      final manifest = ExtensionManifest.parse(_manifest(
        snippets: {
          'rust': {
            'fn': {'body': 'fn main() {}'}
          }
        },
        themes: [
          {
            'id': 'rust-dark',
            'name': 'Rust Dark',
            'colors': {
              'background': '#101010',
              'foreground': '#eeeeee',
              'keyword': '#ff0000',
            },
          }
        ],
      ));

      final engine = HighlightEngine();
      activateExtensions(
        [InstalledExtension(manifest, '/tmp/never-used')],
        engine: engine,
      );

      expect(engine.hasLanguage('rust'), isTrue);
      expect(engine.hasExtension('rs'), isTrue);
      expect(SnippetService.forLanguage('rust').single.prefix, 'fn');
      expect(
          SyntaxThemes.all
              .any((theme) => theme.id == 'ext.com.example.rust.rust-dark'),
          isTrue);
    });

    test('removing a package reverts its grammar in the same session', () async {
      final manifest = ExtensionManifest.parse(_manifest(
        snippets: {
          'rust': {
            'fn': {'body': 'fn main() {}'}
          }
        },
        themes: [
          {
            'id': 'rust-dark',
            'name': 'Rust Dark',
            'colors': {
              'background': '#101010',
              'foreground': '#eeeeee',
              'keyword': '#ff0000',
            },
          }
        ],
      ));

      final engine = HighlightEngine();
      final loader = ExtensionLoader(engine: engine);
      final extension = InstalledExtension(manifest, '/tmp/never-used');
      loader.activateOne(extension);

      expect(engine.forId('rust'), completion(isNotNull));
      expect(SnippetService.forLanguage('rust'), isNotEmpty);
      expect(
        SyntaxThemes.all.any((theme) => theme.id == 'ext.com.example.rust.rust-dark'),
        isTrue,
      );

      final registration = loader.deactivate(extension.manifest.id);

      expect(registration, isNotNull);
      expect(engine.hasLanguage('rust'), isFalse);
      expect(engine.hasExtension('rs'), isFalse);
      expect(await engine.forId('rust'), isNull);
      expect(SnippetService.forLanguage('rust'), isEmpty);
      expect(
        SyntaxThemes.all.any((theme) => theme.id == 'ext.com.example.rust.rust-dark'),
        isFalse,
      );
    });

    test('removal cannot reach a bundled pack or another package', () {
      final rust = ExtensionManifest.parse(_manifest());
      final go = ExtensionManifest.parse(_manifest(
        id: 'com.example.go',
        language: {
          'id': 'go',
          'name': 'Go',
          'extensions': ['go'],
          'grammar': 'go',
        },
      ));

      final engine = HighlightEngine();
      final loader = ExtensionLoader(engine: engine);
      loader.activateOne(InstalledExtension(rust, '/tmp/rust'));
      loader.activateOne(InstalledExtension(go, '/tmp/go'));

      loader.deactivate('com.example.rust');

      expect(engine.hasLanguage('rust'), isFalse);
      expect(engine.hasLanguage('go'), isTrue);
      expect(engine.hasExtension('go'), isTrue);
    });

    test('a package cannot override a bundled language', () {
      final manifest = ExtensionManifest.parse(_manifest(
        language: {
          'id': 'rust',
          'name': 'Fake Rust',
          'extensions': ['rs'],
          'grammar': 'rust',
        },
      ));

      final engine = HighlightEngine();
      final loader = ExtensionLoader(engine: engine);
      loader.activateOne(InstalledExtension(manifest, '/tmp/fake'));

      expect(engine.hasLanguage('rust'), isTrue);
      expect(engine.all.single.id, 'rust');
    });
  });

  group('ExtensionSourceService', () {
    test('merges indexes and keeps one entry per id', () async {
      SharedPreferences.setMockInitialValues({
        'extension_sources': [
          'https://a.example/index.json',
          'https://b.example/index.json',
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient((request) async {
        if (request.url.host == 'a.example') {
          return http.Response(
              jsonEncode({
                'extensions': [
                  {
                    'id': 'com.example.rust',
                    'name': 'Rust',
                    'version': '1.0.0',
                    'download': 'rust.bcext',
                  }
                ]
              }),
              200);
        }
        return http.Response('not found', 404);
      });
      final service = ExtensionSourceService(prefs: prefs, client: client);

      final result = await service.browse();
      expect(result.entries.single.download, 'https://a.example/rust.bcext');
      expect(result.errors, contains('https://b.example/index.json'));
    });

    test('the official index is a default source that appears exactly once',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = ExtensionSourceService(prefs: prefs);

      expect(service.sources, [ExtensionSourceService.defaultSource]);
      expect(
        service.sources
            .where((source) => source == ExtensionSourceService.defaultSource),
        hasLength(1),
      );

      await service.seedDefaults();
      expect(service.sources, [ExtensionSourceService.defaultSource]);
      await service.addSource(ExtensionSourceService.defaultSource);
      expect(service.sources, [ExtensionSourceService.defaultSource]);

      await service.removeSource(ExtensionSourceService.defaultSource);
      expect(service.sources, isEmpty);

      await service.seedDefaults();
      expect(service.sources, isEmpty);

      await service.addSource(ExtensionSourceService.defaultSource);
      expect(service.sources, [ExtensionSourceService.defaultSource]);
      expect(
        prefs.getStringList('extension_sources'),
        [ExtensionSourceService.defaultSource],
      );
    });

    test('the committed official index is valid and lists real packages',
        () async {
      final index = File('extensions-index/index.json');
      final decoded = jsonDecode(await index.readAsString()) as Map;
      final entries = decoded['extensions'] as List;

      expect(entries, isNotEmpty);
      for (final entry in entries.cast<Map>()) {
        final id = entry['id'] as String;
        final download = entry['download'] as String;
        final package = File('extensions-index/$download');
        expect(package.existsSync(), isTrue, reason: 'missing $download');

        final manifest = ExtensionManifest.parse(
          await _readManifestFromArchive(package.path),
        );
        expect(manifest.id, id);
      }
    });
  });
}

Future<String> _readManifestFromArchive(String path) async {
  final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  return utf8.decode(archive.findFile('extension.json')!.content as List<int>);
}

List<int> _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}
