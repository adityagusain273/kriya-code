import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
import 'package:b_code/plugins/host/extension_install_store.dart';
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
}

class _ThrowingClient implements http.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in test');
}
