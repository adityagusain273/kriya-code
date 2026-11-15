import 'package:b_code/core/di.dart';
import 'package:b_code/execution/console_panel.dart';
import 'package:b_code/execution/local/local_runner.dart';
import 'package:b_code/execution/runner_service.dart';
import 'package:b_code/workspace/fs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() {
    sl.registerSingleton<FsService>(FsService('/tmp'));
  });

  tearDown(() {
    sl.reset();
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
    final sheetFinder = find.byType(DraggableScrollableSheet);
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
}
