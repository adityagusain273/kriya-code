import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/security/app_integrity.dart';

const _channel = MethodChannel('bcode.integrity');

const _signerA = 'AAAABBBBCCCCDDDDEEEEFFFF0000111122223333444455556666777788889999';
const _signerB = '1111222233334444555566667777888899990000AAAABBBBCCCCDDDDEEEEFFFF';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void respondWith(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(_channel, (call) async => handler(call));
  }

  void removeHandler() {
    messenger.setMockMethodCallHandler(_channel, null);
  }

  group('AppIntegrity.check', () {
    tearDown(removeHandler);

    test('reports trusted when a signer matches the expected certificate', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[_signerA],
          'signerCount': 1,
        },
      );

      final report = await AppIntegrity.check(expected: <String>[_signerA]);

      expect(report.verdict, IntegrityVerdict.trusted);
      expect(report.isRepackaged, isFalse);
      expect(report.signers, <String>[_signerA]);
      expect(report.signerCount, 1);
      expect(report.reason, isNull);
    });

    test('reports untrusted when the signer is not the expected certificate', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[_signerB],
          'signerCount': 1,
        },
      );

      final report = await AppIntegrity.check(expected: <String>[_signerA]);

      expect(report.verdict, IntegrityVerdict.untrusted);
      expect(report.isRepackaged, isTrue);
      expect(report.reason, contains(_signerB));
    });

    test('accepts any of several expected certificates', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[_signerB],
          'signerCount': 1,
        },
      );

      final report = await AppIntegrity.check(
        expected: <String>[_signerA, _signerB],
      );

      expect(report.verdict, IntegrityVerdict.trusted);
    });

    test('matches the expected certificate case-insensitively', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[_signerA.toLowerCase()],
          'signerCount': 1,
        },
      );

      final report = await AppIntegrity.check(expected: <String>[_signerA]);

      expect(report.verdict, IntegrityVerdict.trusted);
    });

    test('reports unknown when the platform fails', () async {
      respondWith((_) => throw PlatformException(code: 'INTEGRITY_UNAVAILABLE'));

      final report = await AppIntegrity.check(expected: <String>[_signerA]);

      expect(report.verdict, IntegrityVerdict.unknown);
      expect(report.isRepackaged, isFalse);
    });

    test('reports unknown when the platform reports no signer', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[],
          'signerCount': 0,
        },
      );

      final report = await AppIntegrity.check(expected: <String>[_signerA]);

      expect(report.verdict, IntegrityVerdict.unknown);
      expect(report.isRepackaged, isFalse);
    });

    test('reports unknown when the build expects no certificate', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[_signerB],
          'signerCount': 1,
        },
      );

      final report = await AppIntegrity.check();

      expect(report.verdict, IntegrityVerdict.unknown);
      expect(report.isRepackaged, isFalse);
    });

    test('reports the number of signers', () async {
      respondWith(
        (_) => <String, Object?>{
          'signers': <String>[_signerA, _signerB],
          'signerCount': 2,
        },
      );

      final report = await AppIntegrity.check(expected: <String>[_signerA]);

      expect(report.signerCount, 2);
      expect(report.verdict, IntegrityVerdict.trusted);
    });
  });
}
