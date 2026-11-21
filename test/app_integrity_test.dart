import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kriya_code/core/security/app_integrity.dart';

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

  group('AppIntegrity.isEnforceable', () {
    test('is false in debug mode or unconfigured build', () {
      expect(AppIntegrity.isEnforceable, isFalse);
    });

    test('isEnforceableBuild evaluates release mode and expected cert presence', () {
      expect(
        AppIntegrity.isEnforceableBuild(
          releaseMode: true,
          expected: [_signerA],
        ),
        isTrue,
      );
      expect(
        AppIntegrity.isEnforceableBuild(
          releaseMode: false,
          expected: [_signerA],
        ),
        isFalse,
      );
      expect(
        AppIntegrity.isEnforceableBuild(
          releaseMode: true,
          expected: [],
        ),
        isFalse,
      );
      expect(
        AppIntegrity.isEnforceableBuild(
          releaseMode: false,
          expected: [],
        ),
        isFalse,
      );
    });
  });

  group('RepackagedDialog & RepackagedApp', () {
    testWidgets('RepackagedDialog displays tampering warning and triggers onExit', (tester) async {
      var exited = false;
      const report = IntegrityReport(
        verdict: IntegrityVerdict.untrusted,
        signers: [_signerB],
        signerCount: 1,
        reason: 'Untrusted signature',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepackagedDialog(
              report: report,
              onExit: () => exited = true,
            ),
          ),
        ),
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('App Tampering Detected'), findsOneWidget);
      expect(find.textContaining('This build of Kriya Code has been modified'), findsOneWidget);
      expect(find.textContaining('Untrusted signature'), findsOneWidget);
      expect(find.text('Exit App'), findsOneWidget);

      await tester.tap(find.text('Exit App'));
      await tester.pump();
      expect(exited, isTrue);
    });

    testWidgets('RepackagedApp renders MaterialApp with blocking dialog', (tester) async {
      var exited = false;
      const report = IntegrityReport(
        verdict: IntegrityVerdict.untrusted,
        signers: [_signerB],
        signerCount: 1,
      );

      await tester.pumpWidget(
        RepackagedApp(
          report: report,
          onExit: () => exited = true,
        ),
      );

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('App Tampering Detected'), findsOneWidget);
      expect(find.text('Exit App'), findsOneWidget);

      await tester.tap(find.text('Exit App'));
      await tester.pump();
      expect(exited, isTrue);
    });

    testWidgets('showRepackagedDialog displays modal dialog and handles exit', (tester) async {
      var exited = false;
      const report = IntegrityReport(
        verdict: IntegrityVerdict.untrusted,
        signers: [_signerB],
        signerCount: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showRepackagedDialog(
                  context,
                  report: report,
                  onExit: () => exited = true,
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('App Tampering Detected'), findsOneWidget);

      await tester.tap(find.text('Exit App'));
      await tester.pump();
      expect(exited, isTrue);
    });
  });
}
