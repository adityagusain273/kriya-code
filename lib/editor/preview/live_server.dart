import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/di.dart';
import '../../servers/server_monitor.dart';
import 'static_file_handler.dart';

/// Live-reload server for the workspace.
///
/// Binds loopback only, and delegates every request to [StaticFileHandler] for
/// Host/Origin/token validation and path containment.
///
/// The listening URL carries a per-session random token. That is deliberate:
/// the port is ephemeral and therefore enumerable, and without a token any page
/// in any browser on the device could pull the workspace contents into itself
/// through `<img src>` or `<script src>`, neither of which sends an `Origin`
/// header for the CORS checks to catch.
class LiveServer {
  LiveServer(this.rootPath, {Random? random}) : _random = random ?? Random.secure();

  final String rootPath;
  final Random _random;

  HttpServer? _server;
  Future<String>? _starting;
  StaticFileHandler? _handler;

  final _clients = <WebSocket>[];
  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _debounce;

  static const _liveReloadPath = '/__livereload';
  static const _maxLiveReloadClients = 8;

  bool get isRunning => _server != null;

  String? _token;
  int? _port;

  /// The clean URL of the server root, with no session token in it. Only
  /// [urlFor] authorises a client; this getter stays token-free so it can be
  /// shown on screen without leaking the token.
  String? get baseUrl {
    final port = _port;
    if (_server == null || port == null) return null;
    return 'http://127.0.0.1:$port';
  }

  /// A URL for a specific resource path, carrying the session token as a query
  /// parameter. This is the only URL form that includes the token: the first
  /// authorised request exchanges it for an HttpOnly cookie and the server
  /// immediately 302s to the same path without `bct`, so the page never ends
  /// up on a token-bearing URL. `PreviewPage` used to receive `baseUrl` (which
  /// embeds the token as a *query* string) and concatenate `/relative/path`,
  /// producing `.../?bct=tok/path`, which invalidated the token. Keep the
  /// token in the query component of the final path here.
  String? urlFor(String relativePath) {
    final port = _port;
    final token = _token;
    if (_server == null || port == null || token == null) return null;
    final path = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return 'http://127.0.0.1:$port/$path?bct=$token';
  }

  int get clientCount => _clients.length;

  Future<String> start() => _starting ??= _doStart().whenComplete(() => _starting = null);

  Future<String> _doStart() async {
    if (_server != null) return baseUrl!;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final token = _randomToken();

    _server = server;
    _port = port;
    _token = token;
    _handler = StaticFileHandler(
      rootPath: rootPath,
      sessionToken: token,
      transformHtml: (html, nonce) => _injectLiveReload(html, port, nonce),
    );

    server.listen(
      (request) => _handleRequest(request, port),
      onError: (_) {},
    );

    _startWatching();
    sl<ServerMonitor>().addLiveServer(port);
    return baseUrl!;
  }

  Future<void> stop() async {
    _watcher?.cancel();
    _watcher = null;
    _debounce?.cancel();
    _debounce = null;

    final port = _port;
    if (_server != null && port != null) {
      sl<ServerMonitor>().removeLiveServer(port);
    }

    for (final client in _clients.toList()) {
      try {
        await client.close();
      } catch (_) {}
    }
    _clients.clear();

    await _server?.close(force: true);
    _server = null;
    _port = null;
    _token = null;
    _handler = null;
  }

  String _randomToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _startWatching() {
    try {
      _watcher = Directory(rootPath)
          .watch(recursive: true)
          .listen(_onFileEvent);
    } catch (_) {}
  }

  void _onFileEvent(FileSystemEvent event) {
    final path = event.path;
    if (path.endsWith('.swp') ||
        path.endsWith('.tmp') ||
        path.contains('/.git/') ||
        path.contains('/node_modules/')) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _notifyReload);
  }

  void _notifyReload() {
    if (_clients.isEmpty) return;
    final msg = utf8.encode('reload');
    for (final client in _clients.toList()) {
      try {
        client.add(msg);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request, int port) async {
    if (request.uri.path == _liveReloadPath) {
      await _handleUpgrade(request, port);
      return;
    }

    final handler = _handler;
    if (handler == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    await handler.handle(request, port: port);
  }

  Future<void> _handleUpgrade(HttpRequest request, int port) async {
    final response = request.response;

    try {
      final handler = _handler;
      if (handler == null) {
        response.statusCode = HttpStatus.serviceUnavailable;
        await response.close();
        return;
      }

      final hasToken = request.cookies.any(
        (c) => c.name == 'bct' && c.value == handler.sessionToken,
      );
      final queryToken = request.uri.queryParameters['bct'];
      if (!hasToken && queryToken != handler.sessionToken) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }

      final origin = request.headers.value('origin');
      if (origin != null) {
        final uri = Uri.tryParse(origin);
        if (uri == null || uri.scheme != 'http' || uri.port != port) {
          response.statusCode = HttpStatus.forbidden;
          await response.close();
          return;
        }
      }

      // A page in a loop is otherwise a trivial way to exhaust sockets.
      if (_clients.length >= _maxLiveReloadClients) {
        response.statusCode = HttpStatus.serviceUnavailable;
        await response.close();
        return;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      if (_server == null) {
        await socket.close();
        return;
      }
      _clients.add(socket);
      socket.done.then(
        (_) => _clients.remove(socket),
      ).catchError((Object _) => false);
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  String _injectLiveReload(String html, int port, String nonce) {
    // The nonce is the same one the CSP grants for this response; without it
    // script-src would refuse the client.
    final script = '''
<script nonce="$nonce">
(function(){
  function connect(){
    var ws = new WebSocket('ws://127.0.0.1:$port$_liveReloadPath');
    ws.onmessage = function(e){
      if(e.data === 'reload') location.reload();
    };
    ws.onclose = function(){
      setTimeout(connect, 2000);
    };
  }
  connect();
})();
</script>''';

    final bodyClose = html.toLowerCase().lastIndexOf('</body>');
    if (bodyClose != -1) {
      return '${html.substring(0, bodyClose)}$script${html.substring(bodyClose)}';
    }
    return '$html$script';
  }
}