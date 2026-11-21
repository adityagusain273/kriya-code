import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kriya_code/ai/ai_service.dart';
import 'package:kriya_code/ai/kriya_ai_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detectAiProvider', () {
    test('detects Gemini from AIza and AQ prefixes', () {
      expect(detectAiProvider('AIzaSyD-dummy-key-12345'), equals(AiProvider.gemini));
      expect(detectAiProvider('AQ.Ab8RNdummykey12345'), equals(AiProvider.gemini));
      expect(detectAiProvider('AQdummykey12345'), equals(AiProvider.gemini));
    });

    test('detects Groq from gsk_ prefix', () {
      expect(detectAiProvider('gsk_dummygroqkey12345'), equals(AiProvider.groq));
    });

    test('detects Anthropic Claude from sk-ant- prefix', () {
      expect(detectAiProvider('sk-ant-api03-dummyclaude'), equals(AiProvider.anthropic));
    });

    test('detects OpenRouter from sk-or-v1- prefix', () {
      expect(detectAiProvider('sk-or-v1-dummyopenrouter'), equals(AiProvider.openRouter));
    });

    test('detects GitHub Models from ghp_ and github_pat_ prefix', () {
      expect(detectAiProvider('ghp_dummygithubtoken'), equals(AiProvider.github));
      expect(detectAiProvider('github_pat_dummygithubtoken'), equals(AiProvider.github));
    });

    test('detects OpenAI from sk- and sk-proj- prefix', () {
      expect(detectAiProvider('sk-dummyopenaikey'), equals(AiProvider.openAi));
      expect(detectAiProvider('sk-proj-dummyopenaikey'), equals(AiProvider.openAi));
    });

    test('returns unknown for unrecognized prefix', () {
      expect(detectAiProvider('random_key_123'), equals(AiProvider.unknown));
    });
  });

  group('AiService Quota & Key Management', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('stores and clears API key', () async {
      final service = AiService(prefs: prefs);
      expect(await service.getApiKey(), isNull);

      await service.setApiKey('AIzaSyTest123');
      expect(await service.getApiKey(), equals('AIzaSyTest123'));
      expect(await service.getProvider(), equals(AiProvider.gemini));

      await service.setApiKey('');
      expect(await service.getApiKey(), isNull);
    });

    test('tracks daily quota for free tier and allows 3 requests', () async {
      final service = AiService(prefs: prefs);

      expect(service.getRemainingQuotaToday(false), equals(3));
      expect(service.canRequest(false), isTrue);

      await service.recordRequest(false);
      expect(service.getRemainingQuotaToday(false), equals(2));

      await service.recordRequest(false);
      expect(service.getRemainingQuotaToday(false), equals(1));

      await service.recordRequest(false);
      expect(service.getRemainingQuotaToday(false), equals(0));
      expect(service.canRequest(false), isFalse);
    });

    test('pro tier has unlimited quota', () async {
      final service = AiService(prefs: prefs);

      expect(service.getRemainingQuotaToday(true), equals(-1));
      expect(service.canRequest(true), isTrue);

      // Recording requests does not decrement pro tier
      await service.recordRequest(true);
      expect(service.getRemainingQuotaToday(true), equals(-1));
      expect(service.canRequest(true), isTrue);
    });
  });

  group('AiService Completion Dispatch', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('throws AiException when no key configured', () async {
      final service = AiService(prefs: prefs);
      expect(
        () => service.complete(prompt: 'Hello'),
        throwsA(isA<AiException>()),
      );
    });

    test('throws AiException on unrecognized provider key', () async {
      final service = AiService(prefs: prefs);
      await service.setApiKey('random_unknown_key_999');
      expect(
        () => service.complete(prompt: 'Hello'),
        throwsA(isA<AiException>()),
      );
    });

    test('successfully calls Gemini endpoint with header and parses response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('generativelanguage.googleapis.com'));
        expect(request.url.queryParameters['key'], equals('AQ.MockKey'));
        expect(request.headers['x-goog-api-key'], equals('AQ.MockKey'));

        if (request.method == 'GET' && request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-3.8-flash',
                  'supportedGenerationMethods': ['generateContent'],
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['contents'], isNotEmpty);
        expect(request.url.path, contains('gemini-3.8-flash'));

        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Hello from Gemini!'}
                  ]
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiService(prefs: prefs, client: mockClient);
      await service.setApiKey('AQ.MockKey');

      final result = await service.complete(prompt: 'Write hello world in C');
      expect(result, equals('Hello from Gemini!'));
      expect(service.getRemainingQuotaToday(false), equals(2));
    });

    test('Gemini falls back dynamically via ListModels when endpoints return 404', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.contains('gemini-2.0-flash')) {
          return http.Response(
            jsonEncode({'error': {'message': 'Not found', 'code': 404}}),
            404,
          );
        }
        if (request.method == 'POST' && request.url.path.contains('gemini-1.5-flash')) {
          return http.Response(
            jsonEncode({'error': {'message': 'Not found for v1beta', 'code': 404}}),
            404,
          );
        }
        if (request.method == 'GET' && request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-flash',
                  'supportedGenerationMethods': ['generateContent'],
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path.contains('gemini-2.5-flash')) {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Dynamic model response!'}
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = AiService(prefs: prefs, client: mockClient);
      await service.setApiKey('AQ.DynamicKey');

      final result = await service.complete(prompt: 'Hello');
      expect(result, equals('Dynamic model response!'));
    });

    test('successfully calls Groq OpenAI-compatible endpoint', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('api.groq.com'));
        expect(request.headers['authorization'], equals('Bearer gsk_mockgroqkey'));

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Hello from Groq!'}
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiService(prefs: prefs, client: mockClient);
      await service.setApiKey('gsk_mockgroqkey');

      final result = await service.complete(prompt: 'Explain quicksort');
      expect(result, equals('Hello from Groq!'));
    });
  });

  group('KriyaAiContext', () {
    test('builds contextual system prompt with mobile and Kriya Code awareness', () {
      final prompt = KriyaAiContext.buildSystemPrompt(
        filePath: 'lib/main.cpp',
        languageId: 'cpp',
      );

      expect(prompt, contains('Kriya Code'));
      expect(prompt, contains('Android'));
      expect(prompt, contains('Mobile Conciseness'));
      expect(prompt, contains('File: lib/main.cpp'));
      expect(prompt, contains('Language: cpp'));
    });

    test('infers language from file extension correctly', () {
      expect(KriyaAiContext.inferLanguage('main.c'), equals('c'));
      expect(KriyaAiContext.inferLanguage('main.cpp'), equals('cpp'));
      expect(KriyaAiContext.inferLanguage('app.py'), equals('python'));
      expect(KriyaAiContext.inferLanguage('Main.java'), equals('java'));
      expect(KriyaAiContext.inferLanguage('index.html'), equals('html'));
      expect(KriyaAiContext.inferLanguage('script.js'), equals('javascript'));
      expect(KriyaAiContext.inferLanguage('unknown.xyz'), equals('text'));
    });
  });
}
