import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
import 'package:b_code/execution/runtime_download_service.dart';
import 'package:b_code/execution/ui/runtime_download_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;

class FakeRuntimeDownloadService extends RuntimeDownloadService {
  RuntimeDownloadState _currentState = const RuntimeDownloadState();
  bool downloadCalled = false;
  bool cancelCalled = false;

  FakeRuntimeDownloadService(SharedPreferences prefs)
      : super(
          client: http.Client(),
          prefs: prefs,
          runtimesRootResolver: () async => '/tmp',
          extractor: (_) async => true,
        );

  void emitState(RuntimeDownloadState state) {
    _currentState = state;
    notifyListeners();
  }

  @override
  RuntimeDownloadState stateFor(String runtimeId) => _currentState;

  @override
  Future<RuntimePreview?> inspect(String runtimeId) async {
    return const RuntimePreview(
      runtimeId: 'cpython',
      version: '3.14',
      packageCount: 5,
      sizeBytes: 25 * 1024 * 1024,
    );
  }

  @override
  Future<void> download(String runtimeId) async {
    downloadCalled = true;
    emitState(const RuntimeDownloadState(
      phase: RuntimeDownloadPhase.downloading,
      currentPackage: 'python',
      receivedBytes: 12 * 1024 * 1024,
      totalBytes: 24 * 1024 * 1024,
    ));
  }

  @override
  void cancel(String runtimeId) {
    cancelCalled = true;
    emitState(const RuntimeDownloadState(phase: RuntimeDownloadPhase.idle));
  }
}

void main() {
  tearDown(sl.reset);

  testWidgets('shows runtime title and approximate size when idle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fake = FakeRuntimeDownloadService(prefs);
    sl.registerSingleton<RuntimeDownloadService>(fake);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RuntimeDownloadSheet(runtimeId: 'cpython'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Python Runtime'), findsOneWidget);
    expect(find.textContaining('Download & Run'), findsOneWidget);
    expect(find.textContaining('MB'), findsWidgets);
  });

  testWidgets('tapping Download & Run triggers download and reflects downloading state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fake = FakeRuntimeDownloadService(prefs);
    sl.registerSingleton<RuntimeDownloadService>(fake);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RuntimeDownloadSheet(runtimeId: 'cpython'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Download & Run'));
    await tester.pump();

    expect(fake.downloadCalled, isTrue);
    expect(find.text('Fetching python…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error and Retry & Run when download fails', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fake = FakeRuntimeDownloadService(prefs);
    sl.registerSingleton<RuntimeDownloadService>(fake);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RuntimeDownloadSheet(runtimeId: 'cpython'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    fake.emitState(const RuntimeDownloadState(
      phase: RuntimeDownloadPhase.failed,
      error: 'Network timeout',
    ));
    await tester.pump();

    expect(find.text('Network timeout'), findsOneWidget);
    expect(find.textContaining('Retry & Run'), findsOneWidget);
  });

  testWidgets('auto-dismisses with true when phase becomes installed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fake = FakeRuntimeDownloadService(prefs);
    sl.registerSingleton<RuntimeDownloadService>(fake);

    bool? sheetResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                sheetResult =
                    await showRuntimeDownloadSheet(context, runtimeId: 'cpython');
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Open sheet
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Python Runtime'), findsOneWidget);

    // Emit installed
    fake.emitState(const RuntimeDownloadState(phase: RuntimeDownloadPhase.installed));
    await tester.pumpAndSettle();

    // Sheet should have popped with true
    expect(find.text('Python Runtime'), findsNothing);
    expect(sheetResult, isTrue);
  });
}
