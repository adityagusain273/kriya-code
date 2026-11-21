import 'dart:io';

import 'package:kriya_code/core/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashReporter redaction', () {
    test('redacts classic OAuth tokens (ghp_/gho_/ghs_/ghu_/ghr_)', () {
      const body = 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8';
      for (final prefix in ['ghp_', 'gho_', 'ghs_', 'ghu_', 'ghr_']) {
        final token = '$prefix$body';
        final redacted = CrashReporter.redactForTesting('token: $token');
        expect(redacted, isNot(contains(token)), reason: prefix);
        expect(redacted, contains('[REDACTED]'));
      }
    });

    test('redacts fine-grained personal access tokens', () {
      const token = 'github_pat_A1b2C3d4E5f6G7h8I9j0Kl';
      final redacted = CrashReporter.redactForTesting('token: $token');
      expect(redacted, isNot(contains(token)));
      expect(redacted, contains('[REDACTED]'));
    });

    test('redacts Basic authentication credentials', () {
      final redacted = CrashReporter.redactForTesting(
        'Authorization: Basic dXNlcjpwYXNzd29yZA==',
      );
      expect(redacted, isNot(contains('dXNlcjpwYXNzd29yZA==')));
      expect(redacted, contains('[REDACTED]'));
    });

    test('redacts bare Basic credentials', () {
      final redacted = CrashReporter.redactForTesting('Basic dXNlcjEyMzQ=');
      expect(redacted, isNot(contains('dXNlcjEyMzQ=')));
    });

    test('redacts JSON web tokens', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
          'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJVadQssw5c';
      final redacted = CrashReporter.redactForTesting('token: $jwt');
      expect(redacted, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(redacted, contains('[REDACTED]'));
    });

    test('redacts query-string access tokens', () {
      final redacted = CrashReporter.redactForTesting(
        'https://cb/?access_token=abc123def456&state=xyz',
      );
      expect(redacted, isNot(contains('abc123def456')));
      expect(redacted, contains('&state=xyz'));
    });

    test('redacts JSON-form access tokens', () {
      final redacted = CrashReporter.redactForTesting(
        '{"access_token":"supersecretvalue"}',
      );
      expect(redacted, isNot(contains('supersecretvalue')));
      expect(redacted, contains('[REDACTED]'));
    });

    test('still redacts Bearer headers and client secrets', () {
      final redacted = CrashReporter.redactForTesting(
        'Authorization: Bearer abc123 client_secret=shhh789',
      );
      expect(redacted, isNot(contains('abc123')));
      expect(redacted, isNot(contains('shhh789')));
    });

    test('leaves ordinary log lines untouched', () {
      const line = 'at lib/main.dart:42 in init (frame 3)';
      expect(CrashReporter.redactForTesting(line), line);
    });
  });

  group('CrashReporter collection toggle', () {
    // recordZoneError is fire-and-forget (it is a zone callback), so every
    // assertion polls the file rather than reading it once.
    Future<String> waitFor(String needle) async {
      for (var i = 0; i < 40; i++) {
        final log = await CrashReporter.readLog();
        if (log.contains(needle)) return log;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      return CrashReporter.readLog();
    }

    test('writes nothing after collection is switched off', () async {
      final dir = await Directory.systemTemp.createTemp('bcode_crash');
      addTearDown(() => dir.delete(recursive: true));

      CrashReporter.useLogFileForTesting(File('${dir.path}/crash.log'));
      await CrashReporter.init(enabled: true);
      CrashReporter.recordZoneError(StateError('before'), StackTrace.current);
      expect(await waitFor('before'), contains('before'));

      await CrashReporter.setCollectionEnabled(false);
      CrashReporter.recordZoneError(StateError('after'), StackTrace.current);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await CrashReporter.readLog(), isNot(contains('after')));

      await CrashReporter.setCollectionEnabled(true);
      CrashReporter.recordZoneError(StateError('again'), StackTrace.current);
      expect(await waitFor('again'), contains('again'));
    });
  });
}
