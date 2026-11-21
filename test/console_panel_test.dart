import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/execution/console_panel.dart';
import 'package:kriya_code/execution/local/local_runner.dart';
import 'package:kriya_code/execution/runner_service.dart';
import 'package:kriya_code/workspace/fs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class MockLocalRunner extends LocalRunner {
  String? lastStdinRunId;
  String? lastStdinInput;

  @override
  Future<bool> sendStdin(String runId, String input) async {
    lastStdinRunId = runId;
    lastStdinInput = input;
    return true;
  }
}

void main() {
  setUp(() {
    sl.registerSingleton<FsService>(FsService('/tmp'));
  });

  tearDown(() {
    sl.reset();
  });

  test('RunnerService.sendStdin forwards to local runner and echoes to console lines', () {
    final mockLocal = MockLocalRunner();
    final runnerService = RunnerService(local: mockLocal);

    // When not running, sendStdin does nothing
    runnerService.sendStdin('hello');
    expect(mockLocal.lastStdinInput, isNull);
    expect(runnerService.lines, isEmpty);

    // Set running state
    runnerService.setRunningForTesting(true, runId: 'test_run_123');
    runnerService.sendStdin('Alice');

    expect(mockLocal.lastStdinRunId, 'test_run_123');
    expect(mockLocal.lastStdinInput, 'Alice');
    expect(runnerService.lines.length, 1);
    expect(runnerService.lines.first.text, '> Alice');
    expect(runnerService.lines.first.isInput, isTrue);
    expect(runnerService.lines.first.isStderr, isFalse);
  });

  test('RunnerService displays partial prompt without newline immediately and handles continuation', () {
    final mockLocal = MockLocalRunner();
    final runnerService = RunnerService(local: mockLocal);
    runnerService.setRunningForTesting(true, runId: 'test_run');

    // Simulate Python printing 'what: ' without newline
    runnerService.appendChunkForTesting('what: ');
    expect(runnerService.lines.length, 1);
    expect(runnerService.lines.first.text, 'what: ');

    // User inputs 'hello'
    runnerService.sendStdin('hello');
    expect(runnerService.lines.length, 2);
    expect(runnerService.lines[0].text, 'what: ');
    expect(runnerService.lines[1].text, '> hello');
    expect(runnerService.lines[1].isInput, isTrue);

    // Python prints 'hello\n'
    runnerService.appendChunkForTesting('hello\n');
    expect(runnerService.lines.length, 3);
    expect(runnerService.lines[2].text, 'hello');
  });

  testWidgets('console sheet shows input bar when running and hides when stopped', (tester) async {
    final mockLocal = MockLocalRunner();
    final runnerService = RunnerService(local: mockLocal);

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConsolePanel.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Not running: input bar should not be present
    expect(find.byType(ConsoleInputBar), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // Start running
    runnerService.setRunningForTesting(true, runId: 'run_456');
    await tester.pump(const Duration(milliseconds: 100));

    // Running: input bar is visible (CircularProgressIndicator animates, so use pump)
    expect(find.byType(ConsoleInputBar), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Enter input...'), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);

    // Stop running
    runnerService.setRunningForTesting(false);
    await tester.pumpAndSettle();

    // Not running again: input bar is hidden
    expect(find.byType(ConsoleInputBar), findsNothing);
  });

  testWidgets('submitting input via Send button calls runner and clears field', (tester) async {
    final mockLocal = MockLocalRunner();
    final runnerService = RunnerService(local: mockLocal);

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConsolePanel.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    runnerService.setRunningForTesting(true, runId: 'run_interactive');
    await tester.pump();

    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    // Enter text
    await tester.enterText(textFieldFinder, 'John Doe');
    await tester.pump();
    expect(find.text('John Doe'), findsOneWidget);

    // Tap send button
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(mockLocal.lastStdinInput, 'John Doe');
    expect(mockLocal.lastStdinRunId, 'run_interactive');
    // Field is cleared
    expect(find.text('John Doe'), findsNothing);
    // Line echoed in console
    expect(find.text('> John Doe'), findsOneWidget);
  });

  testWidgets('ConsolePanel widget shows input bar when running and hides when stopped', (tester) async {
    final mockLocal = MockLocalRunner();
    final runnerService = RunnerService(local: mockLocal);

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: const MaterialApp(
          home: Scaffold(
            body: ConsolePanel(),
          ),
        ),
      ),
    );

    expect(find.byType(ConsoleInputBar), findsNothing);

    runnerService.setRunningForTesting(true, runId: 'direct_run');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ConsoleInputBar), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'test_line');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(mockLocal.lastStdinInput, 'test_line');
    expect(find.text('> test_line'), findsOneWidget);
  });

  testWidgets('console sheet adjusts for bottom viewInsets when keyboard appears', (tester) async {
    final runnerService = RunnerService(local: LocalRunner());

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConsolePanel.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the console panel
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify sheet is open
    expect(find.text('Output'), findsWidgets);
    expect(find.text('Terminal'), findsOneWidget);

    // Initial position without keyboard inset
    final sheetFinder = find.byKey(const Key('console_sheet_container'));
    expect(sheetFinder, findsOneWidget);
    final initialBottom = tester.getBottomLeft(sheetFinder).dy;

    // Simulate soft keyboard opening with 300 logical px height
    final keyboardHeight = 300.0 * tester.view.devicePixelRatio;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(() => tester.view.resetViewInsets());

    await tester.pumpAndSettle();

    final updatedBottom = tester.getBottomLeft(sheetFinder).dy;
    expect(initialBottom - updatedBottom, 300.0);
  });

  testWidgets('console sheet opens with specified initialIndex', (tester) async {
    final runnerService = RunnerService(local: LocalRunner());

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConsolePanel.show(
                  context,
                  initialIndex: ConsolePanel.tabTerminal,
                ),
                child: const Text('Open Terminal'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Terminal'));
    await tester.pump();

    final tabController = tester.widget<TabBarView>(find.byType(TabBarView)).controller;
    expect(tabController?.index, ConsolePanel.tabTerminal);
  });

  testWidgets('console sheet dismisses when tapping the screen behind it', (tester) async {
    final runnerService = RunnerService(local: LocalRunner());

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConsolePanel.show(context),
                child: const Text('Open Console'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Console'));
    await tester.pumpAndSettle();
    expect(find.text('Output'), findsWidgets);

    // Tap at the top of the screen (y = 50, behind the sheet)
    await tester.tapAt(const Offset(200, 50));
    await tester.pumpAndSettle();

    // Sheet should be dismissed
    expect(find.text('Terminal'), findsNothing);
  });

  testWidgets('console sheet dismisses when back navigation is triggered', (tester) async {
    final runnerService = RunnerService(local: LocalRunner());

    await tester.pumpWidget(
      ChangeNotifierProvider<RunnerService>.value(
        value: runnerService,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConsolePanel.show(context),
                child: const Text('Open Console'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Console'));
    await tester.pumpAndSettle();
    expect(find.text('Output'), findsWidgets);

    // Trigger system back button/gesture
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    final popped = await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.text('Terminal'), findsNothing);
  });
}
