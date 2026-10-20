import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Certificate-pinned HTTP client for GitHub traffic.
///
/// Why this exists
/// ---------------
/// The app previously used `http_certificate_pinning`. That package verifies a
/// pin by opening its own throwaway TLS connection to the host and hashing the
/// leaf certificate; the real request is then issued by `customClient` on a
/// **second, independent** connection with default validation only. An attacker
/// positioned on the network can satisfy the probe and intercept the request
/// that actually carries `Authorization: Bearer <token>`. The pin was therefore
/// decorative.
///
/// Here the check happens inside the handshake of the connection that carries
/// the request: `HttpClient.connectionFactory` builds the socket, default
/// platform validation runs, and the presented leaf is compared against the
/// pin set before a single request byte is written.
///
/// Pin format is the SHA-256 of the leaf certificate's DER encoding, uppercase
/// hex. Regenerate with:
///
///     openssl s_client -connect api.github.com:443 -servername api.github.com \
///       </dev/null 2>/dev/null \
///       | openssl x509 -outform DER \
///       | openssl dgst -sha256 -hex
///
/// dart:io only exposes the leaf (`SecureSocket.peerCertificate`), so the
/// issuing intermediate cannot be pinned. GitHub rotates its leaf on the order
/// of months, so these pins need refreshing when that happens. The failure is a
/// loud `HandshakeException`, never a silent downgrade to unpinned traffic.
class PinnedHttpClient {
  PinnedHttpClient._();

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _requestTimeout = Duration(seconds: 30);

  /// SHA-256 of the leaf certificate DER, per host.
  static const Map<String, Set<String>> pins = {
    'api.github.com': {
      '06E6A4A004329905D4A4E7C0D2C6EC7A632C56443F256424A43CC786951B3149',
    },
    'github.com': {
      '46B601EE08B418CF8A3A1EBFE670BA5CE43BB05A917FA8B2DD087A30471CFC63',
    },
  };

  static Set<String>? pinsFor(String host) => pins[host.toLowerCase()];

  /// Builds a client that pins [host] and applies the standard timeouts.
  ///
  /// Throws [HandshakeException] if the presented certificate is not pinned.
  static http.Client create() {
    final inner = HttpClient()
      ..connectionFactory = _pinnedConnectionFactory
      // A proxy would terminate TLS somewhere this code cannot see, which
      // defeats pinning outright. Refuse to use one.
      ..findProxy = (_) {
        return 'DIRECT';
      }
      ..connectionTimeout = _connectTimeout
      ..idleTimeout = const Duration(seconds: 30);

    return TimeoutClient(IOClient(inner), timeout: _requestTimeout);
  }

  static Future<ConnectionTask<Socket>> _pinnedConnectionFactory(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (proxyHost != null) {
      throw StateError('Refusing to use a proxy for pinned traffic.');
    }
    if (uri.scheme != 'https') {
      throw StateError('Refusing to use cleartext for pinned traffic: $uri');
    }

    final task = await Socket.startConnect(uri.host, uri.port);

    // `HttpClient.connectionTimeout` does not apply once a custom
    // connectionFactory owns the socket, so bound it here.
    final connected = task.socket.timeout(
      _connectTimeout,
      onTimeout: () {
        task.cancel();
        throw TimeoutException(
          'Connecting to ${uri.host}:${uri.port} timed out.',
          _connectTimeout,
        );
      },
    );

    return ConnectionTask.fromSocket<Socket>(
      _secureAndVerify(connected, uri.host),
      task.cancel,
    );
  }

  static Future<Socket> _secureAndVerify(
    Future<Socket> rawSocket,
    String host,
  ) async {
    final raw = await rawSocket;

    // `onBadCertificate` returning false means platform validation is never
    // bypassed. A certificate the system does not trust fails the handshake
    // before the pin comparison is even reached.
    final secure = await SecureSocket.secure(
      raw,
      host: host,
      onBadCertificate: (_) => false,
    );

    try {
      final expected = pinsFor(host);
      if (expected == null) {
        throw HandshakeException('No certificate pin configured for $host.');
      }

      final leaf = secure.peerCertificate;
      if (leaf == null) {
        throw HandshakeException('Server presented no certificate for $host.');
      }

      final actual = sha256.convert(leaf.der).toString().toUpperCase();
      if (!expected.contains(actual)) {
        throw HandshakeException(
          'Certificate pin mismatch for $host. Either the connection was '
          'intercepted, or GitHub rotated its certificate and the pins in '
          'PinnedHttpClient need refreshing. Refusing the connection rather '
          'than continuing unpinned.',
        );
      }
    } catch (_) {
      secure.destroy();
      rethrow;
    }

    return secure;
  }
}

/// Wraps a client so that no call can hang indefinitely.
///
/// The pinned `HttpClient` already bounds connect and idle time, but a response
/// body that trickles slowly would otherwise keep a request alive past any
/// reasonable bound.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(this._inner, {required this.timeout});

  final http.BaseClient _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request).timeout(timeout);
    return http.StreamedResponse(
      _capBody(response.stream, response.contentLength),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Refuses to buffer more than [maxBytes] of a response body.
  static const int maxBytes = 32 * 1024 * 1024;

  Stream<List<int>> _capBody(Stream<List<int>> body, int? contentLength) async* {
    if (contentLength != null && contentLength > maxBytes) {
      throw HttpException('Response too large: $contentLength bytes');
    }

    var received = 0;
    await for (final chunk in body) {
      received += chunk.length;
      if (received > maxBytes) {
        throw HttpException('Response exceeded $maxBytes bytes.');
      }
      yield chunk;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Convenience wrapper for reading a small JSON body with a size ceiling.
Future<dynamic> decodeJsonBody(http.Response response) async {
  final length = response.bodyBytes.length;
  if (length > TimeoutClient.maxBytes) {
    throw HttpException('Response too large: $length bytes');
  }
  return jsonDecode(utf8.decode(response.bodyBytes));
}