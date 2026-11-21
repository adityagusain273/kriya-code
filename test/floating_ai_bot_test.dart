import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kriya_code/ai/ai_service.dart';
import 'package:kriya_code/ai/ui/floating_ai_bot.dart';
import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/lsp/diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AiService aiService;

  setUp(() async {
    sl.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    aiService = AiService(prefs: prefs);
    sl.registerSingleton<AiService>(aiService);
  });

  tearDown(() {
    sl.reset();
  });

  testWidgets('FloatingAiBot renders in normal state when no diagnostics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingAiBot(
                tab: null,
                diagnostics: const [],
                workspaceRoot: '/test/workspace',
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingAiBot), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    // No error bubble
    expect(find.textContaining('Syntax Issue'), findsNothing);
  });

  testWidgets('FloatingAiBot displays waving error bubble when diagnostics are present', (tester) async {
    const errorDiag = Diagnostic(
      offset: 10,
      length: 5,
      line: 3,
      column: 4,
      message: 'Unexpected semicolon',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingAiBot(
                tab: null,
                diagnostics: const [errorDiag],
                workspaceRoot: '/test/workspace',
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);
    expect(find.textContaining('Syntax Issue • Tap to fix'), findsOneWidget);
    expect(find.textContaining('L3: Unexpected semicolon'), findsOneWidget);
  });

  testWidgets('FloatingAiBot dismiss target triggers onDismiss when dragged to bottom', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingAiBot(
                tab: null,
                diagnostics: const [],
                workspaceRoot: '/test/workspace',
                onDismiss: () {
                  dismissed = true;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final botFinder = find.byKey(const ValueKey('bot_button'));
    expect(botFinder, findsOneWidget);

    await tester.drag(botFinder, const Offset(-334, 100));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });
}
