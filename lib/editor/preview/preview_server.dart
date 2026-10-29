import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'static_file_handler.dart';

/// Read-only server backing the in-app preview pane.
///
/// Binds loopback only and delegates every request to [StaticFileHandler]
/// (Host/Origin validation, path containment). Like [LiveServer] it mints a
/// per-session token: the port is ephemeral and therefore enumerable, and a URL
/// alone cannot stop a hostile page from pulling the workspace in through
/// `<img src>`/`<script src>`, which send no `Origin` header that the CORS
/// checks could reject.
class PreviewServer {
  PreviewServer(this.rootPath, {Random? random}) : _random = random ?? Random.secure();

  final String rootPath;
  final Random _random;

  HttpServer? _server;
  Future<String>? _starting;
  StaticFileHandler? _handler;
  String? _token;

  String? get baseUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';

  /// A URL for a specific resource path, with the session token in the query
  /// component of the final path. The first authorised request exchanges the
  /// token for an HttpOnly cookie and 302s to the same path without `bct`, so
  /// the page never ends up on a token-bearing URL; [baseUrl] stays clean for
  /// display purposes. Subsequent requests, including subresources, must
  /// present the cookie.
  String? urlFor(String relativePath) {
    final port = _server?.port;
    final token = _token;
    if (port == null || token == null) return null;
    final path = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return 'http://127.0.0.1:$port/$path?bct=$token';
  }

  Future<String> start() => _starting ??= _doStart().whenComplete(() => _starting = null);

  Future<String> _doStart() async {
    if (_server != null) return baseUrl!;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = _randomToken();
    _server = server;
    _token = token;
    _handler = StaticFileHandler(rootPath: rootPath, sessionToken: token);

    server.listen(
      (request) async {
        final handler = _handler;
        if (handler == null) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        await handler.handle(request, port: server.port);
      },
      onError: (_) {},
    );

    return baseUrl!;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _handler = null;
    _token = null;
  }

  String _randomToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
