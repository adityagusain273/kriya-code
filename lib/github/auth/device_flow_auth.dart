import 'dart:async';
import 'dart:convert';
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

  /// Turns a non-200 from the device-code endpoint into something a person can act on.
  ///
  /// The bare status code was the whole of the old message, and "failed to start
  /// (404)" gave no way to tell a bad client id from a blocked network. Two cases
  /// dominate in practice and they need opposite responses:
  ///
  ///  * GitHub answers 404 with `{"error":"Not Found"}` for this path when something
  ///    between the app and GitHub serves it — a captive portal, or an egress policy
  ///    that filters `github.com/login/*`. `api.github.com` and `github.com` itself
  ///    keep working, so nothing else in the app looks broken and the user has no way
  ///    to tell why. Worth saying in words, because retrying never helps.
  ///  * Everything else — rate limiting, a rejected client id — is GitHub talking,
  ///    and its own `error`/`error_description` is the actionable part, so it is
  ///    surfaced instead of discarded.
  static String describeStartFailure(http.Response response) {
    final status = response.statusCode;
    final detail = _errorDetail(response);

    if (status == 404) {
      return 'GitHub sign-in could not be reached (HTTP 404). '
          '${detail.isEmpty ? '' : 'GitHub said "$detail". '}'
          'This usually means the network is filtering GitHub\'s sign-in endpoints, '
          'such as a work or school network or a VPN. Try a different network. '
          'Everything else in Kriya works without signing in.';
    }

    final suffix = detail.isEmpty ? '' : ': $detail';
    return 'GitHub device flow failed to start (HTTP $status)$suffix';
  }

  /// The `error` / `error_description` pair GitHub returns, if the body is JSON.
  static String _errorDetail(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return _shortBody(response);
      final error = decoded['error'];
      final description = decoded['error_description'];
      final parts = <String>[
        if (error is String && error.isNotEmpty) error,
        if (description is String && description.isNotEmpty) description,
      ];
      return parts.isEmpty ? _shortBody(response) : parts.join(' - ');
    } catch (_) {
      return _shortBody(response);
    }
  }

  static String _shortBody(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return '';
    // A proxy can answer with a whole HTML page; one line of it is not useful.
    final firstLine = body.split('\n').first.trim();
    return firstLine.length > 120 ? '${firstLine.substring(0, 117)}...' : firstLine;
  }

  Future<DeviceFlowSession> start() async {
    // A build without a real OAuth app cannot authenticate. Saying so beats letting
    // the request fail against an unknown client_id and reporting a bare 401, which
    // reads as "GitHub is broken" rather than "this build was not configured".
    if (clientId == AppConstants.unconfiguredClientId) {
      throw StateError(
        'GitHub sign-in is not available in this build. Rebuild with '
        '--dart-define=GITHUB_CLIENT_ID=<your GitHub OAuth App client id>.',
      );
    }
    final response = await client.post(
      Uri.parse(AppConstants.githubDeviceCodeUrl),
      headers: {'Accept': 'application/json'},
      body: {'client_id': clientId, 'scope': AppConstants.githubScopes},
    );
    if (response.statusCode != 200) {
      throw StateError(describeStartFailure(response));
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
    if (error is HandshakeException) return error.message;
    if (error is TimeoutException) return 'The request timed out.';
    if (error is SocketException) return 'Could not reach GitHub.';
    if (error is http.ClientException) return 'Network error: ${error.message}';
    return error.toString();
  }
}