import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/monetization/entitlement_service.dart';
import 'package:kriya_code/monetization/ad_service.dart';
import 'package:kriya_code/monetization/pro_paywall_sheet.dart';
import 'package:kriya_code/monetization/runtime_unlock_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_license.dart';

void main() {
  tearDown(sl.reset);

  group('LocalEntitlementService', () {
    test('initializes with empty set and locks runtimes by default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalEntitlementService(prefs);

      expect(service.isRuntimeUnlocked('cpython'), isFalse);
      expect(service.isRuntimeUnlocked('clang'), isFalse);

      final entitlements = await service.current();
      expect(entitlements.proTier, isFalse);
      expect(entitlements.unlockedRuntimes, isEmpty);
    });

    test('unlocking a runtime persists across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service1 = LocalEntitlementService(prefs);

      await service1.unlockRuntime('cpython');
      expect(service1.isRuntimeUnlocked('cpython'), isTrue);
      expect(service1.isRuntimeUnlocked('clang'), isFalse);

      // Verify persistent re-read from SharedPreferences
      final service2 = LocalEntitlementService(prefs);
      expect(service2.isRuntimeUnlocked('cpython'), isTrue);
      expect(service2.isRuntimeUnlocked('clang'), isFalse);
    });

    test('pro tier unlocks all runtimes and extensions automatically', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalEntitlementService(prefs);

      expect(service.isRuntimeUnlocked('clang'), isFalse);
      expect(service.isExtensionUnlocked('bcode.lang.rust'), isFalse);
      await service.activateWithLicenseKey(validTestLicense);
      expect(service.isRuntimeUnlocked('clang'), isTrue);
      expect(service.isRuntimeUnlocked('anything'), isTrue);
      expect(service.isExtensionUnlocked('bcode.lang.rust'), isTrue);
      expect(service.isExtensionUnlocked('any_extension'), isTrue);

      final entitlements = await service.current();
      expect(entitlements.proTier, isTrue);
    });

    test('a stored pro flag alone does not unlock paid features', () async {
      SharedPreferences.setMockInitialValues({'bcode_pro_tier': true});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalEntitlementService(prefs);
      await service.restore();

      expect(service.isRuntimeUnlocked('clang'), isFalse);
      expect((await service.current()).proTier, isFalse);
    });

    test('a paid licence survives a restart by re-verifying its signature', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await LocalEntitlementService(prefs).activateWithLicenseKey(validTestLicense);

      final restarted = LocalEntitlementService(prefs);
      await restarted.restore();
      expect(restarted.isRuntimeUnlocked('clang'), isTrue);
    });

    test('unlocking an extension persists across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service1 = LocalEntitlementService(prefs);

      expect(service1.isExtensionUnlocked('bcode.lang.kotlin'), isFalse);
      await service1.unlockExtension('bcode.lang.kotlin');
      expect(service1.isExtensionUnlocked('bcode.lang.kotlin'), isTrue);
      expect(service1.isExtensionUnlocked('bcode.lang.rust'), isFalse);

      final service2 = LocalEntitlementService(prefs);
      expect(service2.isExtensionUnlocked('bcode.lang.kotlin'), isTrue);
      expect(service2.isExtensionUnlocked('bcode.lang.rust'), isFalse);
    });
  });

  group('AdMobAdService', () {
    test('uses default sample test ad unit ID when no env override', () {
      final adService = AdMobAdService();
      expect(adService.rewardedAdUnitId, AdMobAdService.testRewardedAdUnitId);
      expect(adService.bannerAdUnitId, AdMobAdService.testBannerAdUnitId);
    });

    test('accepts custom ad unit ID via constructor', () {
      final adService = AdMobAdService(
        rewardedAdUnitId: 'ca-app-pub-custom/123456',
        bannerAdUnitId: 'ca-app-pub-custom/789012',
      );
      expect(adService.rewardedAdUnitId, 'ca-app-pub-custom/123456');
      expect(adService.bannerAdUnitId, 'ca-app-pub-custom/789012');
    });
  });

  group('ProPaywallSheet', () {
    testWidgets('displays features and unlocks Pro with valid license key', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      sl.registerSingleton<EntitlementService>(entitlements);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProPaywallSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('B CODE PRO'), findsOneWidget);
      expect(find.text('Pro Semester Pass (₹49 / 6 Months)'), findsOneWidget);
      expect(find.text('Free Forever (Student Guarantee)'), findsOneWidget);
      expect(find.text('⚡ 100% Zero Ads across the entire app'), findsOneWidget);
      expect(find.text('All Languages: C, C++, Python, Java, Web'), findsOneWidget);
      expect(find.text('₹49 / 6 MONTHS'), findsOneWidget);
      expect(find.text('The Semester Pass (~₹8/month)'), findsOneWidget);
      expect(find.text('Scan QR Code & Pay ₹49'), findsOneWidget);
      expect(find.text('Enter License Key'), findsOneWidget);

      await tester.ensureVisible(find.text('Enter License Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter License Key'));
      await tester.pumpAndSettle();

      expect(find.text('Paste your Pro license key (starts with BCODE.) to activate offline:'), findsOneWidget);

      // Enter invalid key
      await tester.enterText(find.byType(TextField), 'BCODE.fake.invalid');
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid or corrupted license key'), findsOneWidget);
      expect(entitlements.isRuntimeUnlocked('cpython'), isFalse);

      // Enter valid key
      await tester.enterText(find.byType(TextField), validTestLicense);
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(entitlements.isRuntimeUnlocked('cpython'), isTrue);
    });

    testWidgets('tapping Scan QR Code opens payment sheet and allows entering license',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      sl.registerSingleton<EntitlementService>(entitlements);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProPaywallSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Scan QR Code & Pay ₹49'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan QR Code & Pay ₹49'));
      await tester.pumpAndSettle();

      expect(find.text('Scan & Pay ₹49'), findsOneWidget);
      expect(find.textContaining('Paying on this phone?'), findsOneWidget);
      expect(find.text('Copy UPI ID'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Enter License Key & Unlock Pro'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Enter License Key & Unlock Pro'), findsOneWidget);

      await tester.tap(find.text('Enter License Key & Unlock Pro'));
      await tester.pumpAndSettle();

      expect(find.text('Paste your Pro license key (starts with BCODE.) to activate offline:'), findsOneWidget);
    });

    testWidgets('ProPaywallSheet shows active state and allows resetting to free tier',
        (tester) async {
      SharedPreferences.setMockInitialValues({'bcode_license_key': validTestLicense});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      await tester.runAsync(entitlements.restore);
      sl.registerSingleton<EntitlementService>(entitlements);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProPaywallSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Kriya Pro Active (Lifetime Pass)'), 100);
      expect(find.text('Kriya Pro Active (Lifetime Pass)'), findsOneWidget);
      expect(find.text('Reset to Free Tier (For Testing)'), findsOneWidget);

      await tester.tap(find.text('Reset to Free Tier (For Testing)'));
      await tester.pumpAndSettle();

      expect(entitlements.isRuntimeUnlocked(''), isFalse);
    });

    testWidgets('ProPaywallSheet shows Semester Pass active state for 6-month license',
        (tester) async {
      final payload = base64Url.encode('pro:BCODE-DEV-LOCAL:1893456000'.codeUnits).replaceAll('=', '');
      final semesterKey = 'BCODE.$payload.${base64Url.encode(List.filled(256, 1)).replaceAll('=', '')}';
      SharedPreferences.setMockInitialValues({'bcode_license_key': semesterKey});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      sl.registerSingleton<EntitlementService>(entitlements);

      await entitlements.unlockRuntime('');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProPaywallSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Kriya Pro Active (Semester Pass)'), 100);
      expect(find.text('Kriya Pro Active (Semester Pass)'), findsOneWidget);
    });
  });

  group('DuolingoAdUnlockSheet', () {
    testWidgets('requires countdown before granting single-action unlock when offline',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      sl.registerSingleton<EntitlementService>(entitlements);
      sl.registerSingleton<AdService>(AdMobAdService());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuolingoAdUnlockSheet(
              runtimeId: 'clang',
              runtimeTitle: 'C / C++',
              initialCountdownSeconds: 2,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Advertising helps keep Kriya free 🥺'), findsOneWidget);
      expect(find.text('GO AD FREE'), findsOneWidget);
      expect(find.text('Unlocked'), findsNothing);
      expect(entitlements.isRuntimeUnlocked('clang'), isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Unlocked'), findsNothing);
      expect(entitlements.isRuntimeUnlocked('clang'), isFalse);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.textContaining('Continue & Download C / C++'), findsOneWidget);
      expect(entitlements.isRuntimeUnlocked('clang'), isFalse);
    });

    testWidgets('unlocks extension with action label after countdown when ad fails offline',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      sl.registerSingleton<EntitlementService>(entitlements);
      sl.registerSingleton<AdService>(AdMobAdService());

      expect(entitlements.isExtensionUnlocked('bcode.lang.rust'), isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuolingoAdUnlockSheet(
              extensionId: 'bcode.lang.rust',
              title: 'Rust',
              actionLabel: 'Continue & Install Rust',
              initialCountdownSeconds: 1,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Unlocked'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.textContaining('Continue & Install Rust'), findsOneWidget);
      expect(entitlements.isExtensionUnlocked('bcode.lang.rust'), isFalse);
    });

    testWidgets('ensureRuntimeUnlocked returns true for single download without persistent unlock',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = LocalEntitlementService(prefs);
      sl.registerSingleton<EntitlementService>(entitlements);
      sl.registerSingleton<AdService>(AdMobAdService());

      bool? unlocked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  unlocked = await ensureRuntimeUnlocked(
                    ctx,
                    runtimeId: 'clang',
                    runtimeTitle: 'C / C++',
                  );
                },
                child: const Text('Download'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(entitlements.isRuntimeUnlocked('clang'), isFalse);
      expect(find.text('Unlocked'), findsNothing);

      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      expect(find.text('Unlocked'), findsOneWidget);
      expect(entitlements.isRuntimeUnlocked('clang'), isFalse);

      await tester.tap(find.textContaining('Continue & Download C / C++'));
      await tester.pumpAndSettle();

      expect(unlocked, isTrue);
      expect(entitlements.isRuntimeUnlocked('clang'), isFalse);
    });
  });
}
