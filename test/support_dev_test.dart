import 'package:b_code/core/constants.dart';
import 'package:b_code/settings/settings_page.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppConstants has valid UPI details for support', () {
    expect(AppConstants.supportUpiId, '8630024750@yapl');
    expect(AppConstants.supportUpiNumber, '8630024750');
    expect(AppConstants.supportDevName, 'Aditya');
  });

  testWidgets('SettingsPage shows Support Developer tile and opens modal',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
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

    final supportTile = find.text('Support Developer');
    await tester.scrollUntilVisible(
      supportTile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(supportTile, findsOneWidget);

    await tester.tap(supportTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Buy Aditya a Coffee ☕'), findsOneWidget);
    expect(find.text(AppConstants.supportUpiId), findsOneWidget);
    expect(find.text(AppConstants.supportUpiNumber), findsOneWidget);
    expect(find.text('Google Pay'), findsOneWidget);
    expect(find.text('PhonePe'), findsOneWidget);
    expect(find.text('Paytm'), findsOneWidget);

    final closeButton = find.byIcon(Icons.close_rounded);
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Buy Aditya a Coffee ☕'), findsNothing);
  });
}
