import 'package:b_code/core/di.dart';
import 'package:b_code/monetization/entitlement_service.dart';
import 'package:b_code/monetization/license_service.dart';
import 'package:b_code/settings/settings_page.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    sl.reset();
  });

  testWidgets('SettingsPage About tab contains legal disclaimer, updater, and license tiles',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SettingsStore(prefs);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(store: store),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    // Verify Check for Updates tile
    expect(find.text('Check for Updates'), findsOneWidget);

    // Verify Third-Party Licenses tile
    expect(find.text('Third-Party Licenses'), findsOneWidget);

    // Verify Pro Semester Pass copy when free
    expect(
      find.text('₹49 / 6 Months (Semester Pass) — Ad-free & all runtimes unlocked'),
      findsOneWidget,
    );

    // Verify mandatory Microsoft VS Code trademark disclaimer
    expect(
      find.text(
        'B Code is an independent software application developed for mobile devices. '
        'It is not affiliated with, sponsored by, or endorsed by Microsoft Corporation.',
      ),
      findsOneWidget,
    );

    // Verify Third-Party Licenses opens showLicensePage
    await tester.tap(find.text('Third-Party Licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('B Code'), findsAtLeast(1));
  });

  testWidgets('SettingsPage Pro subtitle reflects Semester Pass Active ⚡ when pro is active',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SettingsStore(prefs);

    // Register dummy EntitlementService returning unlocked
    final entitlements = _MockProEntitlementService();
    sl.registerSingleton<EntitlementService>(entitlements);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(store: store),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('Semester Pass Active ⚡'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  test('Custom licenses are registered in LicenseRegistry', () async {
    // Calling SettingsPage causes registration
    final licenses = await LicenseRegistry.licenses.toList();
    final packages = licenses.expand((e) => e.packages).toSet();

    expect(packages.contains('libgit2'), isTrue);
    expect(packages.contains('GCC / Termux packages'), isTrue);
    expect(packages.contains('Python Software Foundation License'), isTrue);
  });
}

class _MockProEntitlementService implements EntitlementService {
  @override
  Future<LicenseValidationResult> activateWithLicenseKey(String licenseKey) async {
    return const LicenseValidationResult(isValid: true, deviceId: 'test');
  }

  @override
  Future<Entitlements> current() async {
    return const Entitlements(proTier: true);
  }

  @override
  bool isExtensionUnlocked(String extensionId) => true;

  @override
  bool isRuntimeUnlocked(String runtimeId) => true;

  @override
  Future<void> restore() async {}

  @override
  Future<void> setProTier(bool isPro) async {}

  @override
  Future<void> unlockExtension(String extensionId) async {}

  @override
  Future<void> unlockRuntime(String runtimeId) async {}
}
