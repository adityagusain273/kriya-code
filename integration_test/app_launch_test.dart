import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:b_code/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Launch', () {
    testWidgets('app launches without errors', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // App should show MaterialApp
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}