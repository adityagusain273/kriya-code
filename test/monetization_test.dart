import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:b_code/core/di.dart';
import 'package:b_code/monetization/entitlement_service.dart';
import 'package:b_code/monetization/ad_service.dart';
import 'package:b_code/monetization/pro_paywall_sheet.dart';
import 'package:b_code/monetization/runtime_unlock_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      await service.setProTier(true);
      expect(service.isRuntimeUnlocked('clang'), isTrue);
      expect(service.isRuntimeUnlocked('anything'), isTrue);
      expect(service.isExtensionUnlocked('bcode.lang.rust'), isTrue);
      expect(service.isExtensionUnlocked('any_extension'), isTrue);

      final entitlements = await service.current();
      expect(entitlements.proTier, isTrue);
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
    const validTestLicense =
        'BCODE.cHJvOnRlc3RAYmNvZGUuZGV2.nDrKf-Gmzu0BvXSHzMlS4PGd_ARgXRAMjn8OXiFO-P99-PIJDN0xtz794tmVtg22w-BnVofpwjA7r1J15Onx9BuquoHtGxoU-yjAZOY7vz7pyXj-KrSG6Y8PQ6sA7tBs5j_PRQNdbJyuxX--WXpZfsiUGnZUP5aMYyInx4IiCwqHwRgNuAhzUD8hOSUITI21EIdOwVGknGKFzErzYtPLoWjHVTU8SooALET62mKK8C0jbIzl_EscGSaQdi5SMw8FT0PUGRcSAniYfibDJz8rKZFstxfoAyX34kztL_hKif9ZeA9cMnlPL9iOFwj9tWIY0oME4v3sGezu64Z1UkYouQ';

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
      expect(find.text('No ads'), findsOneWidget);
      expect(find.text('All compilers unlocked'), findsOneWidget);
      expect(find.text('Scan QR Code & Pay ₹49'), findsOneWidget);
      expect(find.text('Enter License Key'), findsOneWidget);

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
      SharedPreferences.setMockInitialValues({'bcode_pro_tier': true});
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

      await tester.scrollUntilVisible(find.text('B Code Pro Active (Lifetime Pass)'), 100);
      expect(find.text('B Code Pro Active (Lifetime Pass)'), findsOneWidget);
      expect(find.text('Reset to Free Tier (For Testing)'), findsOneWidget);

      await tester.tap(find.text('Reset to Free Tier (For Testing)'));
      await tester.pumpAndSettle();

      expect(entitlements.isRuntimeUnlocked(''), isFalse);
    });
  });

  group('DuolingoAdUnlockSheet', () {
    testWidgets('shows mission title with watery eyes emoji and counts down', (tester) async {
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

      expect(find.text('Advertising helps keep B Code free 🥺'), findsOneWidget);
      expect(find.text('GO AD FREE'), findsOneWidget);

      // Fast forward countdown
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(entitlements.isRuntimeUnlocked('clang'), isTrue);
      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.textContaining('Continue & Download C / C++'), findsOneWidget);
    });

    testWidgets('unlocks extension and shows install action label', (tester) async {
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
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(entitlements.isExtensionUnlocked('bcode.lang.rust'), isTrue);
      expect(find.textContaining('Continue & Install Rust'), findsOneWidget);
    });
  });
}
