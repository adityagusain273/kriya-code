import 'dart:convert';

import 'package:b_code/core/di.dart';
import 'package:b_code/github/auth/device_flow_auth.dart';
import 'package:b_code/github/ui/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  tearDown(() {
    sl.reset();
  });

  testWidgets('renders walkthrough steps and security assurances',
      (tester) async {
    sl.reset();
    sl.registerSingleton<DeviceFlowAuth>(
      DeviceFlowAuth(clientId: 'test-client-id'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(onAuthenticated: (_) {}),
      ),
    );

    expect(find.text('Sign in with GitHub'), findsOneWidget);
    expect(find.text('Connect GitHub'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('Request a one-time code'), findsOneWidget);
    expect(find.text('Authorize on github.com'), findsOneWidget);
    expect(find.text('Start coding'), findsOneWidget);

    expect(find.text('Security & Privacy'), findsOneWidget);
    expect(
      find.text('No passwords entered here. You authorize on GitHub directly.'),
      findsOneWidget,
    );
    expect(
      find.text('Access tokens are stored encrypted on-device only.'),
      findsOneWidget,
    );
    expect(
      find.text('Revocable anytime from GitHub settings or by signing out.'),
      findsOneWidget,
    );

    expect(find.text('Continue with GitHub'), findsOneWidget);
  });

  testWidgets('displays device code and open button when session starts',
      (tester) async {
    sl.reset();
    final client = http_testing.MockClient((request) async {
      if (request.url.toString().contains('/device/code')) {
        return http.Response(
          jsonEncode({
            'device_code': 'dev-1234',
            'user_code': 'ABCD-5678',
            'verification_uri': 'https://github.com/login/device',
            'interval': 5,
            'expires_in': 900,
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'error': 'authorization_pending'}), 200);
    });

    sl.registerSingleton<DeviceFlowAuth>(
      DeviceFlowAuth(clientId: 'test-client-id', client: client),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(onAuthenticated: (_) {}),
      ),
    );

    await tester.ensureVisible(find.text('Continue with GitHub'));
    await tester.tap(find.text('Continue with GitHub'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ABCD-5678'), findsOneWidget);
    expect(find.text('YOUR ONE-TIME DEVICE CODE'), findsOneWidget);
    expect(find.text('Open github.com/login/device'), findsOneWidget);
    expect(find.text('Waiting for authorization on GitHub…'), findsOneWidget);
    expect(find.text('Cancel and start over'), findsOneWidget);

    await tester.ensureVisible(find.text('Cancel and start over'));
    await tester.tap(find.text('Cancel and start over'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
  });
}
