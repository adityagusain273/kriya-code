import 'dart:async';

import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/pinned_http.dart';

class DeviceFlowSession {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  int intervalSeconds;

  /// Absolute deadline derived from the `expires_in` the server sent.
  /// RFC 8628 requires the client to stop polling once it passes.
  final DateTime expiresAt;

  DeviceFlowSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.intervalSeconds,
    required this.expiresAt,
  });

  factory DeviceFlowSession.fromJson(Map<String, Object?> j) {
    final interval = int.tryParse('${j['interval']}') ?? 5;
    final expiresIn = int.tryParse('${j['expires_in']}') ?? 900;
    return DeviceFlowSession(
      deviceCode: j['device_code'] as String,
      userCode: j['user_code'] as String,
      verificationUri: (j['verification_uri'] as String?) ?? 'https://github.com/login/device',
      intervalSeconds: interval,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum DeviceFlowStatus { pending, success, denied, expired, failed }

class DeviceFlowResult {
  final DeviceFlowStatus status;
  final String? token;
  final String? message;

  const DeviceFlowResult(this.status, {this.token, this.message});

  const DeviceFlowResult.failed(String message)
      : this(DeviceFlowStatus.failed, message: message);
}

class DeviceFlowAuth {
  final http.Client client;
  final String clientId;

  DeviceFlowAuth({required this.clientId, http.Client? client})
      : client = client ?? PinnedHttpClient.create();

  void close() => client.close();

  Future<DeviceFlowSession> start() async {
    final response = await client.post(
      Uri.parse(AppConstants.githubDeviceCodeUrl),
      headers: {'Accept': 'application/json'},
      body: {'client_id': clientId, 'scope': AppConstants.githubScopes},
    );
    if (response.statusCode != 200) {
      throw StateError('GitHub device flow failed to start (${response.statusCode}).');
    }
    return DeviceFlowSession.fromJson(
      await decodeJsonBody(response) as Map<String, Object?>,
    );
  }

  Future<DeviceFlowResult> pollOnce(DeviceFlowSession session) async {
    if (session.isExpired) {
      return const DeviceFlowResult(
        DeviceFlowStatus.expired,
        message: 'The sign-in request expired. Please try again.',
      );
    }

    final http.Response response;
    try {
      response = await client.post(
        Uri.parse(AppConstants.githubTokenUrl),
        headers: {'Accept': 'application/json'},
        body: {
          'client_id': clientId,
          'device_code': session.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
    } catch (e) {
      return DeviceFlowResult.failed(_describe(e));
    }

    if (response.statusCode != 200) {
      // Surface the code so a rate limit is distinguishable from a real failure.
      return DeviceFlowResult.failed(
        'GitHub returned ${response.statusCode}.'
        '${response.statusCode == 403 ? ' You may be polling too often.' : ''}',
      );
    }

    final Map<String, Object?> data;
    try {
      data = await decodeJsonBody(response) as Map<String, Object?>;
    } catch (_) {
      return const DeviceFlowResult.failed('GitHub sent a response we could not read.');
    }

    final error = data['error'] as String?;

    if (error == 'authorization_pending') {
      return const DeviceFlowResult(DeviceFlowStatus.pending);
    }

    if (error == 'slow_down') {
      // RFC 8628 §3.5: increase the interval by 5s for all subsequent requests.
      // Re-polling at the same cadence is exactly what GitHub rate-limits.
      session.intervalSeconds += 5;
      return const DeviceFlowResult(DeviceFlowStatus.pending);
    }

    if (error == 'expired_token') {
      return const DeviceFlowResult(
        DeviceFlowStatus.expired,
        message: 'The sign-in request expired. Please try again.',
      );
    }

    if (error != null) {
      return DeviceFlowResult(
        DeviceFlowStatus.denied,
        message: 'GitHub refused the request ($error).',
      );
    }

    final token = data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      return const DeviceFlowResult.failed('GitHub did not return an access token.');
    }

    return DeviceFlowResult(DeviceFlowStatus.success, token: token);
  }

  /// Only allow opening the verification page on github.com over HTTPS.
  /// `verification_uri` is a server-supplied string that was previously handed
  /// straight to the system launcher.
  static bool isSafeVerificationUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' || host.endsWith('.github.com');
  }

  static String _describe(Object error) {
    if (error is http.ClientException) return 'Network error: ${error.message}';
    if (error is HandshakeException) return error.message;
    if (error is TimeoutException) return 'The request timed out.';
    if (error is SocketException) return 'Could not reach GitHub.';
    return 'Request failed.';
  }
}