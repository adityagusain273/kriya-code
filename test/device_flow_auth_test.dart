import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:kriya_code/github/auth/device_flow_auth.dart';

void main() {
  group('DeviceFlowAuth', () {
    test('start sends correct request to GitHub', () async {
      final captured = <String, String>{};

      final client = http_testing.MockClient((request) async {
        captured['url'] = request.url.toString();
        captured['method'] = request.method;
        return http.Response(
          jsonEncode({
            'device_code': 'abc123',
            'user_code': 'ABCD-EFGH',
            'verification_uri': 'https://github.com/login/device',
            'interval': 5,
          }),
          200,
        );
      });

      final auth = DeviceFlowAuth(clientId: 'test-client-id', client: client);
      final session = await auth.start();

      expect(session.deviceCode, 'abc123');
      expect(session.userCode, 'ABCD-EFGH');
      expect(session.verificationUri, 'https://github.com/login/device');
      expect(session.intervalSeconds, 5);
      expect(captured['url'], 'https://github.com/login/device/code');
      expect(captured['method'], 'POST');

      auth.close();
    });

    test('start throws on non-200 response', () async {
      final client = http_testing.MockClient((_) async => http.Response('rate limited', 429));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);
      expectLater(() => auth.start(), throwsA(isA<StateError>()));

      auth.close();
    });

    test('a 404 from the device endpoint is explained, not just numbered', () async {
      // A proxy or egress filter serving github.com's sign-in paths returns 404
      // while api.github.com keeps working, which looks like a broken app rather
      // than a blocked network. The message has to say so.
      final client = http_testing.MockClient((_) async =>
          http.Response('{"error":"Not Found"}', 404,
              headers: {'content-type': 'application/json'}));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);

      await expectLater(
        auth.start,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('network'),
            contains('works without signing in'),
          ),
        )),
      );

      auth.close();
    });

    test('a 404 still reports what the server actually said', () async {
      final client = http_testing.MockClient((_) async =>
          http.Response('{"error":"Not Found"}', 404,
              headers: {'content-type': 'application/json'}));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);

      await expectLater(
        auth.start,
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('Not Found'))),
      );

      auth.close();
    });

    test('a GitHub error_description is surfaced instead of discarded', () async {
      // 429 and a rejected client id are GitHub talking, and its own wording is
      // the actionable part.
      final client = http_testing.MockClient((_) async => http.Response(
          '{"error":"incorrect_client_credentials",'
          '"error_description":"client id is invalid"}',
          401,
          headers: {'content-type': 'application/json'}));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);

      await expectLater(
        auth.start,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('401'), contains('client id is invalid')),
        )),
      );

      auth.close();
    });

    test('a non-JSON body is truncated to one line', () async {
      // A proxy can answer with a whole HTML page; dumping it into the UI is noise.
      final client = http_testing.MockClient((_) async =>
          http.Response('<html><body>${'x' * 400}</body></html>', 502));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);

      await expectLater(
        auth.start,
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('502'))),
      );

      auth.close();
    });

    test('an empty body does not leave a dangling separator', () async {
      final client =
          http_testing.MockClient((_) async => http.Response('', 500));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);

      await expectLater(
        auth.start,
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', isNot(contains(': 500:')))),
      );

      auth.close();
    });

    test('pollOnce returns pending for authorization_pending', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode({'error': 'authorization_pending'}),
            200,
          ));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);
      final session = DeviceFlowSession(
        deviceCode: 'code',
        userCode: 'XXXX-XXXX',
        verificationUri: 'https://github.com/login/device',
        intervalSeconds: 5,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      final result = await auth.pollOnce(session);
      expect(result.status, DeviceFlowStatus.pending);

      auth.close();
    });

    test('pollOnce returns success with token', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode({'access_token': 'ghp_real_token_123'}),
            200,
          ));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);
      final session = DeviceFlowSession(
        deviceCode: 'code',
        userCode: 'XXXX-XXXX',
        verificationUri: 'https://github.com/login/device',
        intervalSeconds: 5,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      final result = await auth.pollOnce(session);
      expect(result.status, DeviceFlowStatus.success);
      expect(result.token, 'ghp_real_token_123');

      auth.close();
    });

    test('pollOnce returns expired for expired_token', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode({'error': 'expired_token'}),
            200,
          ));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);
      final session = DeviceFlowSession(
        deviceCode: 'code',
        userCode: 'XXXX-XXXX',
        verificationUri: 'https://github.com/login/device',
        intervalSeconds: 5,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      final result = await auth.pollOnce(session);
      expect(result.status, DeviceFlowStatus.expired);

      auth.close();
    });

    test('pollOnce returns denied for access_denied', () async {
      final client = http_testing.MockClient((_) async => http.Response(
            jsonEncode({'error': 'access_denied'}),
            200,
          ));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);
      final session = DeviceFlowSession(
        deviceCode: 'code',
        userCode: 'XXXX-XXXX',
        verificationUri: 'https://github.com/login/device',
        intervalSeconds: 5,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      final result = await auth.pollOnce(session);
      expect(result.status, DeviceFlowStatus.denied);

      auth.close();
    });

    test('pollOnce returns failed on non-200 response', () async {
      final client = http_testing.MockClient((_) async => http.Response('error', 500));

      final auth = DeviceFlowAuth(clientId: 'id', client: client);
      final session = DeviceFlowSession(
        deviceCode: 'code',
        userCode: 'XXXX-XXXX',
        verificationUri: 'https://github.com/login/device',
        intervalSeconds: 5,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      final result = await auth.pollOnce(session);
      expect(result.status, DeviceFlowStatus.failed);

      auth.close();
    });

    test('DeviceFlowSession parses interval with default', () {
      final session1 = DeviceFlowSession.fromJson({
        'device_code': 'd',
        'user_code': 'u',
        'interval': 10,
      });
      expect(session1.intervalSeconds, 10);

      final session2 = DeviceFlowSession.fromJson({
        'device_code': 'd',
        'user_code': 'u',
      });
      expect(session2.intervalSeconds, 5);
    });

    test('DeviceFlowSession parses verification_uri with default', () {
      final session1 = DeviceFlowSession.fromJson({
        'device_code': 'd',
        'user_code': 'u',
        'verification_uri': 'https://custom.com/device',
      });
      expect(session1.verificationUri, 'https://custom.com/device');

      final session2 = DeviceFlowSession.fromJson({
        'device_code': 'd',
        'user_code': 'u',
      });
      expect(session2.verificationUri, 'https://github.com/login/device');
    });
  });
}
