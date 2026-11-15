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

    test('pro tier unlocks all runtimes automatically', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalEntitlementService(prefs);

      expect(service.isRuntimeUnlocked('clang'), isFalse);
      await service.setProTier(true);
      expect(service.isRuntimeUnlocked('clang'), isTrue);
      expect(service.isRuntimeUnlocked('anything'), isTrue);

      final entitlements = await service.current();
      expect(entitlements.proTier, isTrue);
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
    testWidgets('displays features and unlocks Pro on tap', (tester) async {
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
      expect(find.textContaining('₹49 Lifetime'), findsOneWidget);

      await tester.tap(find.textContaining('₹49 Lifetime'));
      await tester.pumpAndSettle();

      expect(entitlements.isRuntimeUnlocked('cpython'), isTrue);
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
  });
}
