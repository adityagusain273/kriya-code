import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
import 'package:b_code/plugins/host/extension_install_store.dart';
import 'package:b_code/plugins/packages/extension_installer.dart';
import 'package:b_code/plugins/packages/extension_manifest.dart';
import 'package:b_code/plugins/packages/extension_source.dart';
import 'package:b_code/plugins/ui/extensions_page.dart';
import 'package:b_code/execution/runtime_download_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _StubResolver {
  static Future<String> root() async => '/tmp/bcode_ext_test_runtimes';
}

void main() {
  tearDown(sl.reset);

  testWidgets('installing a language extension triggers download and shows error on failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sl.registerSingleton<ExtensionInstallStore>(ExtensionInstallStore(prefs));

    final downloads = RuntimeDownloadService(
      client: _ThrowingClient(),
      prefs: prefs,
      runtimesRootResolver: _StubResolver.root,
      extractor: (_) async => true,
    );
    sl.registerSingleton<RuntimeDownloadService>(downloads);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExtensionsPage())));
    await tester.pump();

    expect(find.text('Install'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Install').first);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // RuntimeDownloadService.download() catches its own errors and records them
    // on the state object, so the page reports via state rather than by
    // rethrowing. The snackbar therefore comes from the non-installed branch.
    expect(find.textContaining('Download failed'), findsOneWidget);

    // Extension NOT marked installed because download failed
    expect(sl<ExtensionInstallStore>().isInstalled('bcode.lang.python'), isFalse);
  });

  testWidgets('non-language extensions install without popup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sl.registerSingleton<ExtensionInstallStore>(ExtensionInstallStore(prefs));
    sl.registerSingleton<RuntimeDownloadService>(RuntimeDownloadService(
      client: _ThrowingClient(),
      prefs: prefs,
      runtimesRootResolver: _StubResolver.root,
      extractor: (_) async => true,
    ));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExtensionsPage())));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('GitHub'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final githubCard =
        find.ancestor(of: find.text('GitHub'), matching: find.byType(ListTile));
    await tester.tap(
        find.descendant(of: githubCard, matching: find.widgetWithText(FilledButton, 'Install')));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Run GitHub offline?'), findsNothing);
    expect(sl<ExtensionInstallStore>().isInstalled('bcode.github'), isTrue);
  });

  testWidgets('installs a community extension from a source', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sl.registerSingleton<ExtensionInstallStore>(ExtensionInstallStore(prefs));
    sl.registerSingleton<RuntimeDownloadService>(RuntimeDownloadService(
      client: _ThrowingClient(),
      prefs: prefs,
      runtimesRootResolver: _StubResolver.root,
      extractor: (_) async => true,
    ));
    final installer = _FakeInstaller();
    sl.registerSingleton<ExtensionInstaller>(installer);
    sl.registerSingleton<ExtensionSourceService>(_FakeSource(prefs));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExtensionsPage())));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Community extensions'), findsOneWidget);
    expect(find.text('Rust'), findsOneWidget);
    await tester.tap(find.text('Get'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Rust highlighting')),
        findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(installer.cancelled, isTrue);
    expect(installer.committed, isEmpty);
    expect(find.text('Remove'), findsNothing);

    await tester.tap(find.text('Get'));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Install'),
    ));
    await tester.pump();

    expect(installer.committed, hasLength(1));
    expect(find.text('Remove'), findsOneWidget);
  });
}

class _FakeInstaller extends ExtensionInstaller {
  _FakeInstaller() : super(rootDir: '/tmp/bcode_fake_extensions');

  static const _manifest = ExtensionManifest(
    manifestVersion: 1,
    id: 'com.example.rust',
    name: 'Rust',
    version: '1.0.0',
    description: 'Rust highlighting',
    author: 'Example',
  );

  List<InstalledExtension> _installed = const [];
  bool cancelled = false;
  int staged = 0;
  final List<String> committed = [];

  @override
  Future<List<InstalledExtension>> installed() async => _installed;

  @override
  Future<StagedExtension> stageUrl(String url) async {
    staged++;
    return const StagedExtension(
      manifest: _manifest,
      directory: '/tmp/bcode_fake_extensions/.incoming',
      container: '/tmp/bcode_fake_extensions/.incoming',
      readme: 'Rust for B Code.',
    );
  }

  @override
  Future<InstalledExtension> commit(StagedExtension staged) async {
    cancelled = false;
    final extension = InstalledExtension(
      staged.manifest,
      '/tmp/bcode_fake_extensions/${staged.manifest.id}',
    );
    _installed = [extension];
    committed.add(staged.manifest.id);
    return extension;
  }

  @override
  Future<void> discard(StagedExtension staged) async {
    cancelled = true;
  }

  @override
  Future<void> uninstall(String id) async {
    _installed = const [];
  }
}

class _FakeSource extends ExtensionSourceService {
  _FakeSource(SharedPreferences prefs) : super(prefs: prefs);

  @override
  List<String> get sources => const ['https://example.com/index.json'];

  @override
  Future<ExtensionBrowseResult> browse() async => const ExtensionBrowseResult(
        [
          ExtensionCatalogEntry(
            id: 'com.example.rust',
            name: 'Rust',
            version: '1.0.0',
            description: 'Rust highlighting',
            author: 'Example',
            download: 'https://example.com/rust.bcext',
            homepage: '',
            source: 'https://example.com/index.json',
          ),
        ],
        {},
      );
}

class _ThrowingClient implements http.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in test');
}
