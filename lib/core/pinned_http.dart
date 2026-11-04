import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Certificate-pinned HTTP client for GitHub traffic and the runtime
/// repository (the two channels that carry trust-relevant payloads: the OAuth
/// token, and native executables).
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
/// the request: `HttpClient.connectionFactory` builds the socket, and the
/// handshake uses a [SecurityContext] whose only trusted certificate is the CA
/// that signs the host. Nothing else in the system trust store is accepted.
///
/// Why the CA and not the leaf
/// ---------------------------
/// This used to pin the SHA-256 of the leaf certificate. GitHub rotates its
/// leaf every ~90 days and Let's Encrypt every 60, so the pins went stale and
/// every request failed with a `HandshakeException` until a new app release
/// shipped — a routine certificate renewal bricked sign-in, cloning and
/// runtime downloads. Trusting the host's issuing root survives leaf rotation;
/// it only needs an update when the CA itself changes (years, not months).
///
/// Pinning a CA still narrows trust from ~150 system roots to one authority
/// per host, so a rogue CA cannot mint a certificate for api.github.com and
/// read the token. The trade-off is deliberate: a leaf pin is stronger on paper
/// but unusable without a remote pin-update channel.
class PinnedHttpClient {
  PinnedHttpClient._();

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _requestTimeout = Duration(seconds: 30);

  /// The only certificate authority accepted for each host, as PEM.
  ///
  /// Sectigo Public Server Authentication Root E46 (valid to 2038) signs both
  /// github.com hostnames. ISRG Root YR (valid to 2032) signs the Termux
  /// package host. Regenerate the check with:
  ///
  ///     openssl s_client -connect api.github.com:443 -servername api.github.com \
  ///       -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text
  ///
  /// Verify the chain still ends at these roots before releasing. A CA change
  /// fails loudly at handshake time, never silently falling back to unpinned
  /// traffic.
  static const Map<String, String> _issuers = {
    'github.com': _githubIssuer,
    'api.github.com': _githubIssuer,
    'packages.termux.dev': _termuxIssuer,
  };

  static const String _githubIssuer = '''
-----BEGIN CERTIFICATE-----
MIIDRjCCAsugAwIBAgIQGp6v7G3o4ZtcGTFBto2Q3TAKBggqhkjOPQQDAzCBiDEL
MAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNl
eSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMT
JVVTRVJUcnVzdCBFQ0MgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMjEwMzIy
MDAwMDAwWhcNMzgwMTE4MjM1OTU5WjBfMQswCQYDVQQGEwJHQjEYMBYGA1UEChMP
U2VjdGlnbyBMaW1pdGVkMTYwNAYDVQQDEy1TZWN0aWdvIFB1YmxpYyBTZXJ2ZXIg
QXV0aGVudGljYXRpb24gUm9vdCBFNDYwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAR2
+pmpbiDt+dd34wc7qNs9Xzjoq1WmVk/WSOrsfy2qw7LFeeyZYX8QeccCWvkEN/U0
NSt3zn8gj1KjAIns1aeibVvjS5KToID1AZTc8GgHHs3u/iVStSBDHBv+6xnOQ6Oj
ggEgMIIBHDAfBgNVHSMEGDAWgBQ64QmG1M8ZwpZ2dEl23OA1xmNjmjAdBgNVHQ4E
FgQU0SLaTFnxS18mOKqd1u7rDcP7qWEwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB
/wQFMAMBAf8wHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMBEGA1UdIAQK
MAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVz
dC5jb20vVVNFUlRydXN0RUNDQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwNQYI
KwYBBQUHAQEEKTAnMCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3Qu
Y29tMAoGCCqGSM49BAMDA2kAMGYCMQCMCyBit99vX2ba6xEkDe+YO7vC0twjbkv9
PKpqGGuZ61JZryjFsp+DFpEclCVy4noCMQCwvZDXD/m2Ko1HA5Bkmz7YQOFAiNDD
49IWa2wdT7R3DtODaSXH/BiXv8fwB9su4tU=
-----END CERTIFICATE-----
''';

  static const String _termuxIssuer = '''
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
''';

  static final Map<String, SecurityContext> _contexts = {};

  static SecurityContext _contextFor(String host) {
    return _contexts.putIfAbsent(host.toLowerCase(), () {
      final pem = _issuers[host.toLowerCase()];
      if (pem == null) {
        throw HandshakeException('No certificate authority pin configured for $host.');
      }
      return SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(utf8.encode(pem));
    });
  }

  /// Builds a client that pins the configured hosts and applies the standard
  /// timeouts.
  ///
  /// Throws [HandshakeException] if the presented certificate is not pinned.
  /// [maxBytes] raises the body cap for download-heavy callers (a runtime
  /// package can exceed the default 32 MB); [timeout] only bounds
  /// time-to-response-headers, so it does not abort a slow body stream.
  static http.Client create({
    Duration timeout = _requestTimeout,
    int maxBytes = TimeoutClient.defaultMaxBytes,
  }) {
    final inner = HttpClient()
      ..connectionFactory = _pinnedConnectionFactory
      // A proxy would terminate TLS somewhere this code cannot see, which
      // defeats pinning outright. Refuse to use one.
      ..findProxy = (_) {
        return 'DIRECT';
      }
      ..connectionTimeout = _connectTimeout
      ..idleTimeout = const Duration(seconds: 30);

    return TimeoutClient(IOClient(inner), timeout: timeout, maxBytes: maxBytes);
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

    final SecurityContext context;
    try {
      context = _contextFor(host);
    } catch (_) {
      raw.destroy();
      rethrow;
    }

    // Only the pinned CA is in this context, so the handshake fails for any
    // certificate chain that does not terminate at it. Hostname verification
    // still runs, so a valid pinned-CA certificate for a different host is
    // refused too.
    final secure = await SecureSocket.secure(
      raw,
      host: host,
      context: context,
      onBadCertificate: (_) => false,
    );

    try {
      if (secure.peerCertificate == null) {
        throw HandshakeException('Server presented no certificate for $host.');
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
  TimeoutClient(this._inner, {required this.timeout, this.maxBytes = defaultMaxBytes});

  final http.BaseClient _inner;
  final Duration timeout;
  final int maxBytes;

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
  static const int defaultMaxBytes = 32 * 1024 * 1024;

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
  if (length > TimeoutClient.defaultMaxBytes) {
    throw HttpException('Response too large: $length bytes');
  }
  return jsonDecode(utf8.decode(response.bodyBytes));
}