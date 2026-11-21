import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AiProvider {
  gemini('Google Gemini', 'https://aistudio.google.com/app/apikey', 'Free (15 RPM / 1,500 req/day)'),
  groq('Groq', 'https://console.groq.com/keys', 'Fast & Free (Llama 3.3 70B)'),
  openRouter('OpenRouter', 'https://openrouter.ai/keys', 'Multi-model hub'),
  github('GitHub Models', 'https://github.com/settings/tokens', 'Free for GitHub users'),
  openAi('OpenAI', 'https://platform.openai.com/api-keys', 'GPT-4o Mini'),
  anthropic('Anthropic Claude', 'https://console.anthropic.com/', 'Claude 3.5 Haiku'),
  unknown('Custom / Unknown', '', '');

  final String displayName;
  final String keyPortalUrl;
  final String description;

  const AiProvider(this.displayName, this.keyPortalUrl, this.description);
}

AiProvider detectAiProvider(String apiKey) {
  final clean = apiKey.trim();
  if (clean.startsWith('AIza') || clean.startsWith('AQ')) return AiProvider.gemini;
  if (clean.startsWith('gsk_')) return AiProvider.groq;
  if (clean.startsWith('sk-ant-')) return AiProvider.anthropic;
  if (clean.startsWith('sk-or-')) return AiProvider.openRouter;
  if (clean.startsWith('ghp_') || clean.startsWith('github_pat_')) return AiProvider.github;
  if (clean.startsWith('sk-')) return AiProvider.openAi;
  return AiProvider.unknown;
}

class AiException implements Exception {
  final String message;
  final int? statusCode;

  const AiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class AiService {
  static const _secureApiKey = 'ai_user_api_key';
  static const _legacyPrefApiKey = 'ai_user_api_key';
  static const _dailyCountKey = 'ai_daily_usage_count';
  static const _dailyDateKey = 'ai_daily_usage_date';

  static const int freeDailyQuota = 3;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;
  final http.Client _client;

  String? _cachedApiKey;

  AiService({
    required SharedPreferences prefs,
    FlutterSecureStorage? secureStorage,
    http.Client? client,
  })  : _prefs = prefs,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  Future<String?> getApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final key = await _secureStorage.read(key: _secureApiKey);
        if (key != null && key.isNotEmpty) {
          _cachedApiKey = key;
          return key;
        }
      } catch (_) {}
    }

    final legacy = _prefs.getString(_legacyPrefApiKey);
    if (legacy != null && legacy.isNotEmpty) {
      _cachedApiKey = legacy;
      return legacy;
    }
    return null;
  }

  Future<void> setApiKey(String apiKey) async {
    final clean = apiKey.trim();
    _cachedApiKey = clean.isEmpty ? null : clean;
    _workingGeminiModel = null;
    await _prefs.remove('ai_working_gemini_model');
    if (clean.isEmpty) {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          await _secureStorage.delete(key: _secureApiKey);
        } catch (_) {}
      }
      await _prefs.remove(_legacyPrefApiKey);
      return;
    }

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        await _secureStorage.write(key: _secureApiKey, value: clean);
        await _prefs.remove(_legacyPrefApiKey);
        return;
      } catch (_) {}
    }
    await _prefs.setString(_legacyPrefApiKey, clean);
  }

  Future<AiProvider> getProvider() async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return AiProvider.unknown;
    return detectAiProvider(key);
  }

  String _getTodayString() => DateTime.now().toIso8601String().split('T')[0];

  int getUsedQuotaToday() {
    final today = _getTodayString();
    final storedDate = _prefs.getString(_dailyDateKey);
    if (storedDate != today) {
      return 0;
    }
    return _prefs.getInt(_dailyCountKey) ?? 0;
  }

  int getRemainingQuotaToday(bool isPro) {
    if (isPro) return -1;
    final used = getUsedQuotaToday();
    return (freeDailyQuota - used).clamp(0, freeDailyQuota);
  }

  bool canRequest(bool isPro) {
    if (isPro) return true;
    return getRemainingQuotaToday(false) > 0;
  }

  Future<void> recordRequest(bool isPro) async {
    if (isPro) return;
    final today = _getTodayString();
    final storedDate = _prefs.getString(_dailyDateKey);
    var count = _prefs.getInt(_dailyCountKey) ?? 0;
    if (storedDate != today) {
      count = 0;
      await _prefs.setString(_dailyDateKey, today);
    }
    await _prefs.setInt(_dailyCountKey, count + 1);
  }

  Future<String> complete({
    required String prompt,
    String? systemPrompt,
    bool isPro = false,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiException('No API key configured. Paste an API key in Settings.');
    }

    if (!canRequest(isPro)) {
      throw const AiException('Daily free AI limit reached (3/3). Upgrade to Pro for unlimited AI.');
    }

    final provider = detectAiProvider(apiKey);
    final responseText = await _dispatch(
      provider: provider,
      apiKey: apiKey,
      prompt: prompt,
      systemPrompt: systemPrompt,
    );

    await recordRequest(isPro);
    return responseText;
  }

  Future<String> _dispatch({
    required AiProvider provider,
    required String apiKey,
    required String prompt,
    String? systemPrompt,
  }) async {
    switch (provider) {
      case AiProvider.gemini:
        return _callGemini(apiKey, prompt, systemPrompt);
      case AiProvider.groq:
        return _callOpenAiCompatible(
          url: 'https://api.groq.com/openai/v1/chat/completions',
          model: 'llama-3.3-70b-versatile',
          apiKey: apiKey,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
      case AiProvider.openRouter:
        return _callOpenAiCompatible(
          url: 'https://openrouter.ai/api/v1/chat/completions',
          model: 'google/gemini-2.0-flash-exp:free',
          apiKey: apiKey,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
      case AiProvider.github:
        return _callOpenAiCompatible(
          url: 'https://models.inference.ai.azure.com/chat/completions',
          model: 'gpt-4o-mini',
          apiKey: apiKey,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
      case AiProvider.openAi:
        return _callOpenAiCompatible(
          url: 'https://api.openai.com/v1/chat/completions',
          model: 'gpt-4o-mini',
          apiKey: apiKey,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
      case AiProvider.unknown:
        throw const AiException(
          'Unrecognized API key format. Supported:\n'
          '• Google Gemini (AIza... or AQ...)\n'
          '• Groq (gsk_...)\n'
          '• Anthropic Claude (sk-ant-...)\n'
          '• OpenRouter (sk-or-...)\n'
          '• OpenAI (sk-...)\n'
          '• GitHub Models (ghp_...)',
        );
      case AiProvider.anthropic:
        return _callAnthropic(apiKey, prompt, systemPrompt);
    }
  }

  String? _workingGeminiModel;

  Future<List<String>> fetchSupportedGeminiModels(String apiKey) async {
    final clean = apiKey.trim();
    if (clean.isEmpty) return [];

    final encodedKey = Uri.encodeComponent(clean);
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': clean,
    };

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$encodedKey',
    );
    final res = await _client.get(uri, headers: headers);
    if (res.statusCode != 200) {
      final errorData = _safeJsonDecode(res.body);
      final msg = errorData?['error']?['message'] as String? ??
          'Failed to list models (${res.statusCode})';
      throw AiException(msg, res.statusCode);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final models = (data['models'] as List?) ?? [];
    final supported = <String>[];

    for (final item in models) {
      if (item is Map) {
        final methods = (item['supportedGenerationMethods'] as List?)?.cast<dynamic>() ?? [];
        if (methods.contains('generateContent')) {
          final rawName = item['name'] as String? ?? '';
          if (rawName.isNotEmpty) {
            supported.add(rawName.replaceFirst('models/', ''));
          }
        }
      }
    }

    return supported;
  }

  Future<void> setActiveGeminiModel(String model) async {
    _workingGeminiModel = model;
    await _prefs.setString('ai_working_gemini_model', model);
  }

  Future<String> verifyAndResolveActiveGeminiModel(String apiKey) async {
    final supported = await fetchSupportedGeminiModels(apiKey);
    if (supported.isEmpty) {
      throw const AiException('No models supporting content generation found for this API key.');
    }

    const preferredPriority = [
      'gemini-3.5-flash-lite',
      'gemini-flash-lite-latest',
      'gemini-3.6-flash',
      'gemini-3.5-flash',
      'gemini-3.8-flash-lite',
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-flash-latest',
    ];

    final sorted = List<String>.from(supported);
    sorted.sort((a, b) {
      final idxA = preferredPriority.indexOf(a);
      final idxB = preferredPriority.indexOf(b);
      final rankA = idxA == -1 ? 999 : idxA;
      final rankB = idxB == -1 ? 999 : idxB;
      return rankA.compareTo(rankB);
    });

    final encodedKey = Uri.encodeComponent(apiKey.trim());
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey.trim(),
    };
    final probeBody = jsonEncode({
      'contents': [
        {
          'parts': [{'text': 'ping'}]
        }
      ]
    });

    for (final candidate in sorted) {
      if (candidate.contains('tts') || candidate.contains('image')) continue;
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$candidate:generateContent?key=$encodedKey',
        );
        final res = await _client.post(uri, headers: headers, body: probeBody)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          _workingGeminiModel = candidate;
          await _prefs.setString('ai_working_gemini_model', candidate);
          return candidate;
        }
      } catch (_) {}
    }

    final fallback = sorted.firstWhere(
      (m) => !m.contains('tts') && !m.contains('image'),
      orElse: () => sorted.first,
    );
    _workingGeminiModel = fallback;
    await _prefs.setString('ai_working_gemini_model', fallback);
    return fallback;
  }

  Future<String> resolveActiveGeminiModel(String apiKey) async {
    if (_workingGeminiModel != null) return _workingGeminiModel!;

    final cachedPref = _prefs.getString('ai_working_gemini_model');
    if (cachedPref != null && cachedPref.isNotEmpty) {
      _workingGeminiModel = cachedPref;
      return cachedPref;
    }

    return verifyAndResolveActiveGeminiModel(apiKey);
  }

  Future<String> _callGemini(String apiKey, String prompt, String? systemPrompt) async {
    const preferredPriority = [
      'gemini-3.5-flash-lite',
      'gemini-flash-lite-latest',
      'gemini-3.6-flash',
      'gemini-3.5-flash',
      'gemini-3.8-flash-lite',
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-flash-latest',
    ];

    final contents = <Map<String, dynamic>>[];
    final requestBody = <String, dynamic>{
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'system_instruction': {
          'parts': [{'text': systemPrompt}]
        },
      'contents': contents,
    };

    contents.add({
      'role': 'user',
      'parts': [{'text': prompt}],
    });

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    };

    final encodedKey = Uri.encodeComponent(apiKey);
    final activeModel = await resolveActiveGeminiModel(apiKey);

    http.Response? res;
    String? currentModel = activeModel;

    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$currentModel:generateContent?key=$encodedKey',
      );
      res = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      res = null;
    }

    if (res == null || res.statusCode != 200) {
      _workingGeminiModel = null;
      await _prefs.remove('ai_working_gemini_model');
      try {
        final allSupported = await fetchSupportedGeminiModels(apiKey);
        final sortedFallbacks = List<String>.from(allSupported);
        sortedFallbacks.sort((a, b) {
          final idxA = preferredPriority.indexOf(a);
          final idxB = preferredPriority.indexOf(b);
          final rankA = idxA == -1 ? 999 : idxA;
          final rankB = idxB == -1 ? 999 : idxB;
          return rankA.compareTo(rankB);
        });

        for (final fallbackModel in sortedFallbacks) {
          if (fallbackModel == currentModel) continue;
          if (fallbackModel.contains('tts') || fallbackModel.contains('image')) continue;

          try {
            final retryUri = Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$fallbackModel:generateContent?key=$encodedKey',
            );
            final retryRes = await _client.post(
              retryUri,
              headers: headers,
              body: jsonEncode(requestBody),
            ).timeout(const Duration(seconds: 12));
            if (retryRes.statusCode == 200) {
              res = retryRes;
              currentModel = fallbackModel;
              _workingGeminiModel = fallbackModel;
              await _prefs.setString('ai_working_gemini_model', fallbackModel);
              break;
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (res != null && res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'] as String? ?? '';
        }
      }
      return '';
    }

    if (res == null) {
      throw const AiException('Network connection error or timeout while calling Gemini.');
    }

    final errorData = _safeJsonDecode(res.body);
    final msg = errorData?['error']?['message'] as String? ??
        'Gemini API error (${res.statusCode})';
    throw AiException(msg, res.statusCode);
  }

  Future<String> _callOpenAiCompatible({
    required String url,
    required String model,
    required String apiKey,
    required String prompt,
    String? systemPrompt,
  }) async {
    final uri = Uri.parse(url);
    final messages = <Map<String, String>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    try {
      final res = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.2,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final msg = choices[0]['message'] as Map<String, dynamic>?;
          return msg?['content'] as String? ?? '';
        }
        return '';
      }

      final errorData = _safeJsonDecode(res.body);
      final msg = errorData?['error']?['message'] as String? ?? 'AI error (${res.statusCode})';
      throw AiException(msg, res.statusCode);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException('Network connection error: $e');
    }
  }

  Future<String> _callAnthropic(String apiKey, String prompt, String? systemPrompt) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    try {
      final res = await _client.post(
        uri,
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-3-5-haiku-20241022',
          'max_tokens': 2048,
          if (systemPrompt != null && systemPrompt.isNotEmpty) 'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final content = data['content'] as List?;
        if (content != null && content.isNotEmpty) {
          return content[0]['text'] as String? ?? '';
        }
        return '';
      }

      final errorData = _safeJsonDecode(res.body);
      final msg = errorData?['error']?['message'] as String? ?? 'Anthropic API error (${res.statusCode})';
      throw AiException(msg, res.statusCode);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException('Network connection error: $e');
    }
  }

  Map<String, dynamic>? _safeJsonDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
