import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
import 'package:b_code/execution/runtime_download_service.dart';
import 'package:b_code/execution/ui/downloads_page.dart';
import 'package:b_code/monetization/entitlement_service.dart';
import 'package:b_code/plugins/host/extension_install_store.dart';
import 'package:b_code/plugins/ui/extensions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class _FakeRuntimeDownloadService extends RuntimeDownloadService {
  _FakeRuntimeDownloadService(SharedPreferences prefs)
      : super(
          client: http.Client(),
          prefs: prefs,
          runtimesRootResolver: () async => '/tmp',
          extractor: (_) async => true,
        );

  @override
  RuntimeDownloadState stateFor(String runtimeId) =>
      const RuntimeDownloadState();

  @override
  Future<RuntimePreview?> inspect(String runtimeId) async => null;
}

void main() {
  tearDown(sl.reset);

  testWidgets('ExtensionsPage has Extensions and Runtimes tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sl.registerSingleton<ExtensionInstallStore>(ExtensionInstallStore(prefs));
    sl.registerSingleton<RuntimeDownloadService>(_FakeRuntimeDownloadService(prefs));
    sl.registerSingleton<EntitlementService>(LocalEntitlementService(prefs));

    await tester.pumpWidget(
      const MaterialApp(
        home: ExtensionsPage(),
      ),
    );
    await tester.pump();

    expect(find.text('Extensions'), findsWidgets);
    expect(find.text('Runtimes'), findsOneWidget);

    await tester.tap(find.text('Runtimes'));
    await tester.pumpAndSettle();

    expect(find.byType(RuntimesView), findsOneWidget);
    expect(find.text('Python Runtime'), findsOneWidget);
  });

  testWidgets('DownloadsPage displays RuntimesView with Language Runtimes title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sl.registerSingleton<RuntimeDownloadService>(_FakeRuntimeDownloadService(prefs));
    sl.registerSingleton<EntitlementService>(LocalEntitlementService(prefs));

    await tester.pumpWidget(
      const MaterialApp(
        home: DownloadsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Language Runtimes'), findsOneWidget);
    expect(find.byType(RuntimesView), findsOneWidget);
    expect(find.text('Python Runtime'), findsOneWidget);
  });
}
