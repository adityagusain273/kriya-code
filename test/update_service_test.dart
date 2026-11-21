import 'dart:convert';
import 'package:kriya_code/core/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateService.isNewerVersion', () {
    test('detects newer semantic versions', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', 'v1.1.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', 'V2.0.0'), isTrue);
    });

    test('detects older or equal versions', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', 'v1.0.0'), isFalse);
    });

    test('handles build numbers correctly', () {
      expect(UpdateService.isNewerVersion('1.0.0+10', 'v1.0.0+11'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0+10', '1.0.0+10'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0+10', '1.0.0+9'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0+10', '1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0+1'), isTrue);
    });

    test('handles empty or malformed inputs safely', () {
      expect(UpdateService.isNewerVersion('', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', ''), isFalse);
    });
  });

  group('UpdateService.checkForUpdates', () {
    test('returns UpdateInfo with hasUpdate: true when release is newer', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), UpdateService.latestReleaseEndpoint);
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.1.0',
            'html_url': 'https://github.com/advaiti/b_code/releases/tag/v1.1.0',
          }),
          200,
        );
      });

      final service = UpdateService(client: mockClient);
      final info = await service.checkForUpdates(currentVersion: '1.0.0+10');

      expect(info, isNotNull);
      expect(info!.hasUpdate, isTrue);
      expect(info.latestVersion, 'v1.1.0');
      expect(info.releaseUrl, 'https://github.com/advaiti/b_code/releases/tag/v1.1.0');
    });

    test('returns UpdateInfo with hasUpdate: false when already up to date', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.0+10',
            'html_url': 'https://github.com/advaiti/b_code/releases/tag/v1.0.0+10',
          }),
          200,
        );
      });

      final service = UpdateService(client: mockClient);
      final info = await service.checkForUpdates(currentVersion: '1.0.0+10');

      expect(info, isNotNull);
      expect(info!.hasUpdate, isFalse);
    });

    test('returns null when GitHub API fails', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = UpdateService(client: mockClient);
      final info = await service.checkForUpdates(currentVersion: '1.0.0+10');

      expect(info, isNull);
    });
  });

  group('UpdateService.showUpdateDialog', () {
    testWidgets('shows lightweight update dialog with correct text and buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    const UpdateService().showUpdateDialog(
                      context,
                      releaseUrl: 'https://github.com/advaiti/b_code/releases/latest',
                      latestVersion: 'v1.1.0',
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(
        find.text('New Kriya update available! Tap to download the latest compilers and fixes.'),
        findsOneWidget,
      );
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update Available'), findsNothing);
    });
  });
}
