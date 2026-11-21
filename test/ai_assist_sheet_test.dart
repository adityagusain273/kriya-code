import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kriya_code/ai/ai_service.dart';
import 'package:kriya_code/ai/kriya_ai_context.dart';
import 'package:kriya_code/ai/ui/ai_assist_sheet.dart';
import 'package:kriya_code/core/di.dart';
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

  testWidgets('AiAssistSheet renders key setup when no key is set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AiAssistSheet(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kriya AI Assistant'), findsOneWidget);
    expect(find.text('Paste your AI API key once to activate. Supports Gemini, Groq, OpenAI, Claude, OpenRouter, and GitHub Models.'), findsOneWidget);
    expect(find.text('Get Free Gemini Key'), findsOneWidget);
    expect(find.text('Save Key'), findsOneWidget);
  });

  testWidgets('AiAssistSheet detects Gemini prefix in real time', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AiAssistSheet(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = find.byType(TextField);
    expect(input, findsOneWidget);

    await tester.enterText(input, 'AQ.Ab8RNSampleKey123');
    await tester.pump();

    expect(find.textContaining('Detected: Google Gemini'), findsOneWidget);
  });

  testWidgets('AiAssistSheet shows assistant view when key is configured', (tester) async {
    await aiService.setApiKey('AIzaSyValidConfiguredKey');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AiAssistSheet(
            initialCode: 'int x = 10;',
            contextDescription: 'test.c',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kriya AI Assistant'), findsOneWidget);
    // Active Context chip displays the target file name
    expect(find.text('test.c'), findsOneWidget);
    expect(find.text('Active Context'), findsOneWidget);
    expect(find.text('Explain Code'), findsOneWidget);
    expect(find.text('Find & Fix Bugs'), findsOneWidget);
    expect(find.text('Add Comments'), findsOneWidget);
    expect(find.textContaining('Free: 3/3 left today'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  test('KriyaAiContext includes fileContent, openFiles, and zero-paste instruction', () {
    final prompt = KriyaAiContext.buildSystemPrompt(
      filePath: 'Calculator.py',
      languageId: 'python',
      workspaceFolder: 'Python course',
      openFiles: ['Calculator.py', 'utils.py'],
      fileContent: 'num1 = float(input())\nprint(num1)',
    );

    expect(prompt, contains('Workspace Folder: Python course'));
    expect(prompt, contains('Active Target File: Calculator.py'));
    expect(prompt, contains('Open Files in Editor: Calculator.py, utils.py'));
    expect(prompt, contains('num1 = float(input())'));
    expect(prompt, contains('never ask them to paste or include the code'));
  });
}
