import 'package:kriya_code/editor/exit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dirty exit lists the files and discards on request',
      (tester) async {
    ExitChoice? choice;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  choice = await showExitDialog(
                    context,
                    dirtyFiles: ['/w/lib/main.dart', '/w/lib/app.dart'],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Save before you leave?'), findsOneWidget);
    expect(find.text('2 files have unsaved changes.'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('app.dart'), findsOneWidget);
    expect(find.text('Save and exit'), findsOneWidget);

    await tester.tap(find.text('Discard changes and exit'));
    await tester.pumpAndSettle();

    expect(choice, ExitChoice.discard);
  });

  testWidgets('clean exit offers a plain exit and no discard', (tester) async {
    ExitChoice? choice;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  choice = await showExitDialog(context, dirtyFiles: const []);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Leave Kriya?'), findsOneWidget);
    expect(find.text('Discard changes and exit'), findsNothing);

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(choice, ExitChoice.exit);
  });

  testWidgets('caps the file list and system back keeps the editor open',
      (tester) async {
    ExitChoice? choice;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  choice = await showExitDialog(
                    context,
                    dirtyFiles: const [
                      '/w/a.dart',
                      '/w/b.dart',
                      '/w/c.dart',
                      '/w/d.dart',
                      '/w/e.dart',
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('c.dart'), findsOneWidget);
    expect(find.text('e.dart'), findsNothing);
    expect(find.text('and 2 more'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Save before you leave?'), findsNothing);
    expect(choice, isNull);
  });
}
