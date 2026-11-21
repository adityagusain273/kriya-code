import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:kriya_code/core/di.dart';
import 'package:kriya_code/github/api_client.dart';
import 'package:kriya_code/github/ui/cloud_build_sheet.dart';
import 'package:kriya_code/monetization/entitlement_service.dart';
import 'package:kriya_code/monetization/license_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeEntitlementService implements EntitlementService {
  bool isPro;
  FakeEntitlementService({this.isPro = false});

  @override
  Future<void> restore() async {}

  @override
  Future<Entitlements> current() async => Entitlements(proTier: isPro);

  @override
  bool isRuntimeUnlocked(String runtimeId) => isPro;

  @override
  Future<void> unlockRuntime(String runtimeId) async {}

  @override
  bool isExtensionUnlocked(String extensionId) => isPro;

  @override
  Future<void> unlockExtension(String extensionId) async {}

  @override
  Future<void> setProTier(bool pro) async {
    isPro = pro;
  }

  @override
  Future<LicenseValidationResult> activateWithLicenseKey(String licenseKey) async {
    isPro = true;
    return LicenseValidationResult.valid;
  }
}

void main() {
  tearDown(sl.reset);

  group('CloudBuildSheet daily quota helpers', () {
    test('getDailyBuildCount returns 0 and initializes today when empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final count = await CloudBuildSheet.getDailyBuildCount(prefs);
      expect(count, 0);
      expect(prefs.getString(CloudBuildSheet.cloudBuildQuotaDateKey),
          CloudBuildSheet.todayDateString());
    });

    test('incrementDailyBuildCount increments for today', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await CloudBuildSheet.incrementDailyBuildCount(prefs);
      expect(await CloudBuildSheet.getDailyBuildCount(prefs), 1);

      await CloudBuildSheet.incrementDailyBuildCount(prefs);
      expect(await CloudBuildSheet.getDailyBuildCount(prefs), 2);
    });

    test('getDailyBuildCount resets to 0 on a new day', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = CloudBuildSheet.todayDateString(yesterday);
      SharedPreferences.setMockInitialValues({
        CloudBuildSheet.cloudBuildQuotaDateKey: yesterdayStr,
        CloudBuildSheet.cloudBuildQuotaCountKey: 2,
      });
      final prefs = await SharedPreferences.getInstance();

      final count = await CloudBuildSheet.getDailyBuildCount(prefs);
      expect(count, 0);
      expect(prefs.getString(CloudBuildSheet.cloudBuildQuotaDateKey),
          CloudBuildSheet.todayDateString());
    });
  });

  group('CloudBuildSheet quota enforcement', () {
    late int dispatchCount;
    late GitHubApiClient api;

    setUp(() {
      dispatchCount = 0;
      final client = http_testing.MockClient((request) async {
        if (request.url.path.endsWith('/actions/workflows')) {
          return http.Response(
            jsonEncode({
              'total_count': 1,
              'workflows': [
                {
                  'id': 42,
                  'name': 'Android APK',
                  'path': '.github/workflows/build-apk.yml',
                  'state': 'active',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/branches')) {
          return http.Response(
            jsonEncode([
              {'name': 'main', 'commit': {'sha': 'abc'}},
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/dispatches')) {
          dispatchCount++;
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/runs')) {
          return http.Response(
            jsonEncode({
              'total_count': 0,
              'workflow_runs': [],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      api = GitHubApiClient(
        client: client,
        downloadClient: http_testing.MockClient((_) async => http.Response('', 200)),
      );
      sl.registerSingleton<GitHubApiClient>(api);
    });

    tearDown(() {
      api.close();
    });

    testWidgets('free tier user can trigger build and count increments up to 2',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final entitlements = FakeEntitlementService(isPro: false);
      sl.registerSingleton<EntitlementService>(entitlements);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CloudBuildSheet(
              token: 'token',
              owner: 'owner',
              repo: 'repo',
              defaultBranch: 'main',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Trigger Build');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(dispatchCount, 1);
      expect(await CloudBuildSheet.getDailyBuildCount(prefs), 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('free tier user hits quota at 2 builds and paywall is shown',
        (tester) async {
      final today = CloudBuildSheet.todayDateString();
      SharedPreferences.setMockInitialValues({
        CloudBuildSheet.cloudBuildQuotaDateKey: today,
        CloudBuildSheet.cloudBuildQuotaCountKey: 2,
      });
      final entitlements = FakeEntitlementService(isPro: false);
      sl.registerSingleton<EntitlementService>(entitlements);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CloudBuildSheet(
              token: 'token',
              owner: 'owner',
              repo: 'repo',
              defaultBranch: 'main',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Trigger Build');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('B CODE PRO'), findsOneWidget);
      expect(find.text('Pro Semester Pass (₹49 / 6 Months)'), findsOneWidget);
      expect(dispatchCount, 0);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('pro user is not restricted by daily build quota', (tester) async {
      final today = CloudBuildSheet.todayDateString();
      SharedPreferences.setMockInitialValues({
        CloudBuildSheet.cloudBuildQuotaDateKey: today,
        CloudBuildSheet.cloudBuildQuotaCountKey: 5,
      });
      final entitlements = FakeEntitlementService(isPro: true);
      sl.registerSingleton<EntitlementService>(entitlements);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CloudBuildSheet(
              token: 'token',
              owner: 'owner',
              repo: 'repo',
              defaultBranch: 'main',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Trigger Build');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(dispatchCount, 1);
      expect(find.text('B CODE PRO'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
