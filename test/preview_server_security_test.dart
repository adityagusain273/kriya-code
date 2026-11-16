import 'dart:convert';
import 'dart:io';

import 'package:b_code/core/di.dart';
import 'package:b_code/editor/preview/live_server.dart';
import 'package:b_code/editor/preview/preview_server.dart';
import 'package:b_code/servers/server_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Response {
  final int status;
  final String head;
  final String body;

  _Response(this.status, this.head, this.body);

  List<String> header(String name) => head
      .split('\r\n')
      .skip(1)
      .where((line) => line.toLowerCase().startsWith('${name.toLowerCase()}:'))
      .map((line) => line.substring(name.length + 2).trim())
      .toList();

  bool headerContains(String name, String part) =>
      header(name).any((value) => value.toLowerCase().contains(part.toLowerCase()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sl.registerSingleton<ServerMonitor>(
      ServerMonitor(await SharedPreferences.getInstance()),
    );
  });

  tearDownAll(() {
    sl.reset();
  });

  // Sends one raw HTTP request and reads the whole response, so tests control
  // the Host/Origin/cookie headers and the exact request-target bytes.
  Future<_Response> send(int port, String request) async {
    final socket = await Socket.connect('127.0.0.1', port);
    socket.write('$request\r\n\r\n');
    final raw = await utf8.decoder.bind(socket).join();
    socket.destroy();
    final split = raw.indexOf('\r\n\r\n');
    final head = raw.substring(0, split);
    final body = raw.substring(split + 4);
    final status = int.parse(head.split('\r\n').first.split(' ')[1]);
    return _Response(status, head, body);
  }

  String get(int port, String path, {String? host, String? origin, String? cookie}) {
    return [
      'GET $path HTTP/1.1',
      'Host: ${host ?? '127.0.0.1:$port'}',
      if (origin != null) 'Origin: $origin',
      if (cookie != null) 'Cookie: $cookie',
      'Connection: close',
    ].join('\r\n');
  }

  group('PreviewServer (StaticFileHandler behind it)', () {
    late Directory tempDir;
    late PreviewServer server;
    late int port;
    late String token;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('bcode_preview_test');
      File('${tempDir.path}/index.html')
          .writeAsStringSync('<p>hello page</p><script>alert(1)</script>');
      Directory('${tempDir.path}/sub').createSync();
      File('${tempDir.path}/sub/hello.js').writeAsStringSync('console.log(1)');
      server = PreviewServer(tempDir.path);
      await server.start();
      port = Uri.parse(server.baseUrl!).port;
      token = Uri.parse(server.urlFor('')!).queryParameters['bct']!;
    });

    tearDownAll(() async {
      await server.stop();
      await tempDir.delete(recursive: true);
    });

    test('exchanges the query token for an HttpOnly cookie and 302s to a clean URL',
        () async {
      final res = await send(port, get(port, '/index.html?bct=$token'));
      expect(res.status, 302);
      expect(res.header('Location'), ['/index.html']);
      expect(res.header('Location').first, isNot(contains(token)));
      final cookieHeader = res.header('Set-Cookie').first;
      expect(cookieHeader, contains('bct=$token'));
      expect(cookieHeader, contains('HttpOnly'));
      expect(cookieHeader, contains('Path=/'));
      expect(cookieHeader, contains('SameSite=Strict'));
    });

    test('bootstrap redirect keeps other query parameters and the path', () async {
      final res = await send(port, get(port, '/sub/hello.js?bct=$token&keep=yes'));
      expect(res.status, 302);
      expect(res.header('Location'), ['/sub/hello.js?keep=yes']);
    });

    test('root bootstrap redirect lands on /', () async {
      final res = await send(port, get(port, '/?bct=$token'));
      expect(res.status, 302);
      expect(res.header('Location'), ['/']);
    });

    test('a wrong token gets 403, not a redirect', () async {
      final res = await send(port, get(port, '/?bct=wrong'));
      expect(res.status, 403);
      expect(res.header('Set-Cookie'), isEmpty);
    });

    test('a missing token gets 403', () async {
      final res = await send(port, get(port, '/'));
      expect(res.status, 403);
    });

    test('the cookie authorises every later request and served pages are clean',
        () async {
      final res = await send(port, get(port, '/index.html', cookie: 'bct=$token'));
      expect(res.status, 200);
      expect(res.body, contains('<p>hello page</p>'));
      expect(res.body, isNot(contains(token)));
    });

    test('every response carries the mandated CSP', () async {
      final html = await send(port, get(port, '/index.html', cookie: 'bct=$token'));
      expect(html.status, 200);
      final policy = html.header('Content-Security-Policy').first;
      expect(policy, contains("default-src 'self'"));
      expect(policy, contains("connect-src 'self'"));
      expect(policy, contains("img-src 'self' data: blob:"));
      expect(policy, contains("script-src 'self'"));
      expect(policy, contains("style-src 'self' 'unsafe-inline'"));
      expect(policy, contains("font-src 'self' data:"));
      expect(policy, contains("object-src 'none'"));
      expect(policy, contains("base-uri 'none'"));
      expect(policy, contains("frame-ancestors 'none'"));
      expect(policy, contains("form-action 'none'"));
      // The preview server injects nothing: inline scripts get no nonce.
      expect(policy, contains("script-src 'self';"));

      final js = await send(port, get(port, '/sub/hello.js', cookie: 'bct=$token'));
      expect(js.status, 200);
      expect(js.header('Content-Security-Policy').first, contains("connect-src 'self'"));
    });

    test('existing guards still hold: Host, Origin, token, paths, symlink', () async {
      // Host header validation (DNS rebinding). Rebinding domains exist
      // precisely at `<attacker-host>:<port>` and with no port at all.
      for (final host in ['evil.tld:$port', 'evil.tld', '127.0.0.1:9']) {
        final res = await send(port, get(port, '/', host: host));
        expect(res.status, 421, reason: 'host $host must be rejected');
      }

      // Loopback hostnames stay allowed — auth is what gates them.
      final localhostNoCookie = await send(port, get(port, '/', host: 'localhost:$port'));
      expect(localhostNoCookie.status, 403);

      // Cross-origin request rejection.
      final crossOrigin = await send(
        port,
        get(port, '/', origin: 'http://evil.tld', cookie: 'bct=$token'),
      );
      expect(crossOrigin.status, 403);

      // Wrong cookie value.
      final wrongCookie = await send(port, get(port, '/', cookie: 'bct=WRONG'));
      expect(wrongCookie.status, 403);

      // Path traversal out of the workspace.
      final outside = File('${tempDir.path}/../secret.txt')
        ..writeAsStringSync('SECRET');
      final victimToken = 'bct=$token';
      for (final path in [
        '/../secret.txt',
        '/..%2Fsecret.txt',
        '/%2e%2e/secret.txt',
        '/sub/..%2F..%2Fsecret.txt',
        '/sub/%2e%2e/%2e%2e/secret.txt',
      ]) {
        final res = await send(port, get(port, path, cookie: victimToken));
        expect(res.status, 404, reason: 'path $path must not be served');
      }

      // A symlink inside the workspace must not point at app-private storage.
      final outsideDir = await Directory.systemTemp.createTemp('bcode_outside_test');
      final linked = File('${outsideDir.path}/true-secret.txt')
        ..writeAsStringSync('FROM OUTSIDE');
      Link('${tempDir.path}/sub/link.lnk').createSync(linked.path);
      final symlinkRes = await send(port, get(port, '/sub/link.lnk', cookie: victimToken));
      expect(symlinkRes.status, 404);
      expect(linked.readAsStringSync(), 'FROM OUTSIDE');
      await outsideDir.delete(recursive: true);
      outside.deleteSync();
    });

    test('dotfiles and dot-directories are never served', () async {
      // A previewed page is same-origin with the server, so it can fetch its
      // own workspace. Secret material must not be among what comes back.
      File('${tempDir.path}/.env').writeAsStringSync('GITHUB_TOKEN=hunter2');
      Directory('${tempDir.path}/.git').createSync();
      File('${tempDir.path}/.git/config').writeAsStringSync('[remote "origin"]');
      Directory('${tempDir.path}/.ssh').createSync();
      File('${tempDir.path}/.ssh/id_ed25519').writeAsStringSync('PRIVATE KEY');

      for (final path in [
        '/.env',
        '/.git/config',
        '/.ssh/id_ed25519',
        '/sub/../.env',
        '/%2eenv',
      ]) {
        final res = await send(port, get(port, path, cookie: 'bct=$token'));
        expect(res.status, 404, reason: 'path $path must not be served');
        expect(res.body, isNot(contains('hunter2')));
        expect(res.body, isNot(contains('PRIVATE KEY')));
      }

      // Ordinary files in the same folder still serve.
      final ok = await send(port, get(port, '/sub/hello.js', cookie: 'bct=$token'));
      expect(ok.status, 200);
    });

    test('methods other than GET/HEAD are rejected', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      socket.write(
          'POST /index.html HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n'
          'Cookie: bct=$token\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
      final raw = await utf8.decoder.bind(socket).join();
      socket.destroy();
      expect(raw.contains('405 Method Not Allowed'), isTrue);
    });
  });

  group('LiveServer', () {
    late Directory tempDir;
    late LiveServer server;
    late int port;
    late String token;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('bcode_live_test');
      File('${tempDir.path}/index.html')
          .writeAsStringSync('<p>live page</p><script>alert(1)</script>');
      File('${tempDir.path}/app.js').writeAsStringSync('console.log(2)');
      server = LiveServer(tempDir.path);
      await server.start();
      port = Uri.parse(server.baseUrl!).port;
      token = Uri.parse(server.urlFor('')!).queryParameters['bct']!;
    });

    tearDownAll(() async {
      await server.stop();
      await tempDir.delete(recursive: true);
    });

    test('the displayed base URL carries no token', () {
      expect(server.baseUrl, 'http://127.0.0.1:$port');
      expect(server.baseUrl, isNot(contains(token)));
    });

    test('bootstrap: query token exchanged for HttpOnly cookie, clean redirect',
        () async {
      final res = await send(port, get(port, '/?bct=$token'));
      expect(res.status, 302);
      expect(res.header('Location'), ['/']);
      expect(res.header('Location').first, isNot(contains(token)));
      final cookieHeader = res.header('Set-Cookie').first;
      expect(cookieHeader, contains('bct=$token'));
      expect(cookieHeader, contains('HttpOnly'));
      expect(cookieHeader, contains('SameSite=Strict'));
    });

    test('CSP blocks egress but keeps live reload: ws origin + matching nonce',
        () async {
      final res = await send(port, get(port, '/', cookie: 'bct=$token'));
      expect(res.status, 200);
      final policy = res.header('Content-Security-Policy').first;

      // Every remote egress sink is pinned to the loopback origin.
      expect(policy, contains("default-src 'self'"));
      expect(policy, contains("connect-src 'self'"));
      expect(policy, contains("img-src 'self' data: blob:"));
      expect(policy, contains("style-src 'self' 'unsafe-inline'"));
      expect(policy, contains("font-src 'self' data:"));
      expect(policy, contains("object-src 'none'"));
      expect(policy, contains("base-uri 'none'"));
      expect(policy, contains("frame-ancestors 'none'"));
      expect(policy, contains("form-action 'none'"));

      // The WebSocket the injected client dials is explicitly allowed.
      expect(policy, contains("connect-src 'self' ws://127.0.0.1:$port"));

      // script-src admits nothing but the nonce-bearing injected client.
      final scriptMatch =
          RegExp(r"script-src 'self' 'nonce-([^']*)'").firstMatch(policy);
      expect(scriptMatch, isNotNull);
      final nonce = scriptMatch!.group(1)!;
      expect(nonce, isNotEmpty);
      final scriptSrc = scriptMatch.group(0)!;
      expect(scriptSrc, isNot(contains('unsafe-inline')));

      // The injected client carries exactly that nonce and dials the allowed ws.
      expect(res.body, contains('<script nonce="$nonce">'));
      expect(res.body, contains('ws://127.0.0.1:$port/__livereload'));
    });

    test('non-HTML responses on the live server also name the ws origin', () async {
      final res = await send(port, get(port, '/app.js', cookie: 'bct=$token'));
      expect(res.status, 200);
      final policy = res.header('Content-Security-Policy').first;
      expect(policy, contains("connect-src 'self' ws://127.0.0.1:$port"));
    });

    test('still without auth: 403', () async {
      final res = await send(port, get(port, '/'));
      expect(res.status, 403);
    });

    test('missing root index.html serves empty fallback with 200 instead of 404', () async {
      final emptyDir = Directory.systemTemp.createTempSync('live_server_empty_');
      final emptyServer = LiveServer(emptyDir.path);
      await emptyServer.start();
      final emptyPort = Uri.parse(emptyServer.baseUrl!).port;
      final emptyToken = Uri.parse(emptyServer.urlFor('')!).queryParameters['bct']!;
      try {
        final res = await send(emptyPort, get(emptyPort, '/', cookie: 'bct=$emptyToken'));
        expect(res.status, 200);
        expect(res.body, contains('No index.html detected'));
        expect(res.body, contains('Live Server Active'));
      } finally {
        await emptyServer.stop();
        emptyDir.deleteSync(recursive: true);
      }
    });
  });
}
