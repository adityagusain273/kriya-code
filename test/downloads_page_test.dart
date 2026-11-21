import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/execution/runtime_download_service.dart';
import 'package:kriya_code/execution/ui/downloads_page.dart';
import 'package:kriya_code/monetization/entitlement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class FakeRuntimeDownloadService extends RuntimeDownloadService {
  final Map<String, RuntimeDownloadState> _states = {};
  bool cancelCalled = false;
  String? cancelledRuntimeId;

  FakeRuntimeDownloadService(SharedPreferences prefs)
      : super(
          client: http.Client(),
          prefs: prefs,
          runtimesRootResolver: () async => '/tmp',
          extractor: (_) async => true,
        );

  void emitState(String runtimeId, RuntimeDownloadState state) {
    _states[runtimeId] = state;
    notifyListeners();
  }

  @override
  RuntimeDownloadState stateFor(String runtimeId) =>
      _states[runtimeId] ?? const RuntimeDownloadState();

  @override
  Future<RuntimePreview?> inspect(String runtimeId) async {
    return RuntimePreview(
      runtimeId: runtimeId,
      version: '1.0.0',
      packageCount: 3,
      sizeBytes: 15 * 1024 * 1024,
    );
  }

  @override
  void cancel(String runtimeId) {
    cancelCalled = true;
    cancelledRuntimeId = runtimeId;
    emitState(runtimeId, const RuntimeDownloadState(phase: RuntimeDownloadPhase.idle));
  }
}

void main() {
  tearDown(sl.reset);

  testWidgets('shows cancel button during download and tapping it cancels download', (tester) async {
    SharedPreferences.setMockInitialValues({'bcode_unlocked_runtimes': ['clang']});
    final prefs = await SharedPreferences.getInstance();

    final fake = FakeRuntimeDownloadService(prefs);
    sl.registerSingleton<RuntimeDownloadService>(fake);
    sl.registerSingleton<EntitlementService>(LocalEntitlementService(prefs));

    await tester.pumpWidget(
      const MaterialApp(
        home: DownloadsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);

    fake.emitState('clang', const RuntimeDownloadState(
      phase: RuntimeDownloadPhase.downloading,
      currentPackage: 'clang',
      receivedBytes: 5 * 1024 * 1024,
      totalBytes: 20 * 1024 * 1024,
    ));
    await tester.pump();

    final cancelButton = find.widgetWithText(TextButton, 'Cancel');
    expect(cancelButton, findsOneWidget);

    await tester.tap(cancelButton);
    await tester.pump();

    expect(fake.cancelCalled, isTrue);
    expect(fake.cancelledRuntimeId, 'clang');
    expect(find.text('Cancel'), findsNothing);
  });
}
