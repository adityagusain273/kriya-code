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

  testWidgets('FloatingAiBot does not render floating AI button when no diagnostics (Requirement 2)', (tester) async {
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
    // User requirement: No floating AI logo when there's no error
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    expect(find.byIcon(Icons.smart_toy_rounded), findsNothing);
  });

  testWidgets('FloatingAiBot displays waving robotic hand error bot when diagnostics are present', (tester) async {
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
    expect(find.byIcon(Icons.waving_hand_rounded), findsOneWidget);
    expect(find.textContaining('Click me to fix this'), findsOneWidget);
    expect(find.textContaining('L3: Unexpected semicolon'), findsOneWidget);
  });

  testWidgets('FloatingAiBot dismiss button hides the bot', (tester) async {
    const errorDiag = Diagnostic(
      offset: 10,
      length: 5,
      line: 3,
      column: 4,
      message: 'Unexpected semicolon',
    );

    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingAiBot(
                tab: null,
                diagnostics: const [errorDiag],
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
    await tester.pump(const Duration(milliseconds: 500));

    final closeIcon = find.byIcon(Icons.close_rounded);
    expect(closeIcon, findsOneWidget);

    await tester.tap(closeIcon);
    await tester.pump();

    expect(dismissed, isTrue);
    expect(find.byIcon(Icons.smart_toy_rounded), findsNothing);
  });
}
