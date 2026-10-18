import 'dart:async';
import 'dart:io';

import 'static_file_handler.dart';

/// Read-only server backing the in-app preview pane.
///
/// The URL is never shown to the user and the WebView is the only client, so
/// there is no session token here — Host and Origin validation plus path
/// containment still apply. Request handling is delegated to
/// [StaticFileHandler] so the preview and the live server cannot drift apart
/// again.
class PreviewServer {
  PreviewServer(this.rootPath);

  final String rootPath;

  HttpServer? _server;
  Future<String>? _starting;
  StaticFileHandler? _handler;

  String? get baseUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';

  Future<String> start() => _starting ??= _doStart().whenComplete(() => _starting = null);

  Future<String> _doStart() async {
    if (_server != null) return baseUrl!;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _handler = StaticFileHandler(rootPath: rootPath);

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
  }
}