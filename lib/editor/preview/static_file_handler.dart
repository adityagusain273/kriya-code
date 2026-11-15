import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Serves a single directory over loopback HTTP for the preview and live-reload
/// features.
///
/// Both the preview server and the live server used to carry their own copy of
/// this logic. The copies had already diverged — one of them sent
/// `Access-Control-Allow-Origin: *` and the other did not — so every fix had to
/// be applied twice and a miss was silent. There is one implementation now.
///
/// Threat model
/// ------------
/// The server binds to 127.0.0.1 on an ephemeral port. That is not by itself a
/// boundary: every app on the device, every adb-forwarded connection, and every
/// website the user visits can reach that socket. Four layers apply:
///
///  1. Host header validation. Defeats DNS rebinding, where an attacker
///     resolves `evil.tld` to 127.0.0.1 and the browser then treats the request
///     as same-origin, which would make every other defence irrelevant.
///  2. Origin rejection. A browser sends `Origin` on cross-origin `fetch`, XHR,
///     and CORS requests. Anything outside the loopback origin is refused
///     outright rather than merely having its response header omitted.
///  3. An unguessable session token, when supplied. Layer 2 alone does not stop
///     `<img src>` or `<script src>`, which are sent without an `Origin` header
///     and which would otherwise hand the contents of the user's source files to
///     a hostile page — a `<script src>` executes them as JavaScript. The token
///     arrives as a one-time query parameter, is exchanged for an HttpOnly
///     cookie, and the request is immediately redirected to a URL without it —
///     so no page URL, history entry, or `location.search` ever carries the
///     token. Every later request must present the cookie, including
///     subresources.
///  4. Content-Security-Policy. Layers 1–3 do not gate what the page sends
///     *out*: `fetch`/XHR/beacon/WebSocket egress is invisible to
///     `shouldOverrideUrlLoading`, which Android only invokes for main-frame
///     navigations. The CSP header closes that channel by blocking every
///     non-loopback request the page can make.
///
/// Containment uses `p.isWithin`, which compares path components. A bare
/// `startsWith` would accept `/srv/projects-backup` when serving `/srv/projects`.
class StaticFileHandler {
  StaticFileHandler({
    required this.rootPath,
    this.sessionToken,
    this.transformHtml,
    this.maxFileBytes = 64 * 1024 * 1024,
    Random? random,
  }) : _random = random ?? Random.secure();

  final String rootPath;

  /// When non-null, every request must present this token, either as the
  /// `bct` query parameter (which sets the cookie and redirects to a clean
  /// URL) or as the cookie itself.
  final String? sessionToken;

  /// Applied to HTML responses with the per-response CSP nonce the injected
  /// inline `<script>` must carry to pass `script-src`.
  final String Function(String html, String nonce)? transformHtml;

  /// Refuse to serve anything larger than this.
  final int maxFileBytes;

  final Random _random;

  static const _loopbackHosts = {'127.0.0.1', 'localhost', '::1', '[::1]'};

  /// True when [origin] is an http origin on loopback for [port]. Shared with
  /// the live-reload WebSocket upgrade, which needs the same check before it
  /// upgrades the connection.
  static bool isLoopbackHttpOrigin(String? origin, int port) {
    if (origin == null) return true;
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    if (uri.scheme != 'http') return false;
    if (uri.port != port) return false;
    return _loopbackHosts.contains(uri.host.toLowerCase());
  }

  static const _cookieName = 'bct';

  /// `HttpHeaders` has no `originHeader` constant.
  static const _originHeader = 'origin';

  /// Blocks every network request the page can make except to this exact
  /// origin: `fetch`/XHR/beacon/WebSocket (`connect-src`), images (`img-src`),
  /// scripts and workers (`script-src`), styles (`style-src`), fonts
  /// (`font-src`), plugins (`object-src`), framed subresources
  /// (`default-src`), form posts (`form-action`), and `<base>` rewriting
  /// (`base-uri`). `frame-ancestors` keeps other sites from embedding this
  /// server. Inline `style` stays allowed because hand-written HTML relies on
  /// it; inline `script` is not allowed — the one script the app itself
  /// injects is admitted per-response through a nonce.
  static final _basePolicy = <String>[
    "default-src 'self'",
    "connect-src 'self'",
    "img-src 'self' data: blob:",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "font-src 'self' data:",
    "object-src 'none'",
    "base-uri 'none'",
    "frame-ancestors 'none'",
    "form-action 'none'",
  ].join('; ');

  static final _securityHeaders = <String, String>{
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Cache-Control': 'no-store',
    'Content-Security-Policy': _basePolicy,
  };

  Future<void> handle(HttpRequest request, {required int port}) async {
    final response = request.response;

    try {
      for (final entry in _securityHeaders.entries) {
        response.headers.set(entry.key, entry.value);
      }

      // The live server is the only one with a WebSocket endpoint; `'self'`
      // cannot be relied on to cover `ws://` (a different scheme from the
      // page's `http://`), so name the exact origin the injected client dials.
      if (transformHtml != null) {
        response.headers
            .set('Content-Security-Policy', _policy(port: port));
      }

      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set('Allow', 'GET, HEAD');
        await response.close();
        return;
      }

      if (!_isAllowedHost(request, port)) {
        await _fail(request, HttpStatus.misdirectedRequest);
        return;
      }

      if (!_isAllowedOrigin(request, port)) {
        await _fail(request, HttpStatus.forbidden);
        return;
      }

      final token = sessionToken;
      if (token != null && !_hasValidCookie(request, token)) {
        final supplied = request.uri.queryParameters[_cookieName];
        if (supplied == null || !constantTimeEquals(supplied, token)) {
          await _fail(request, HttpStatus.forbidden);
          return;
        }
        await _bootstrap(request, token);
        return;
      }

      final target = await _resolveTarget(request.uri.path);
      if (target == null) {
        await _fail(request, HttpStatus.notFound);
        return;
      }

      final length = await target.length();
      if (length > maxFileBytes) {
        await _fail(request, HttpStatus.requestEntityTooLarge);
        return;
      }

      final rel = p.relative(target.path, from: rootPath);
      response.headers.contentType = ContentType.parse(mimeFor(rel));

      if (request.method == 'HEAD') {
        response.headers.set('Content-Length', '$length');
        await response.close();
        return;
      }

      if (rel.toLowerCase().endsWith('.html')) {
        final html = await target.readAsString();
        final inject = transformHtml;
        if (inject == null) {
          response.write(html);
        } else {
          // A fresh nonce per response, shared between the policy and the
          // injected client, so no other inline script can pass `script-src`.
          final nonce = _nonce();
          response.headers.set(
            'Content-Security-Policy',
            _policy(port: port, nonce: nonce),
          );
          response.write(inject(html, nonce));
        }
        await response.close();
      } else {
        await target.openRead().pipe(response);
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  /// Rejects any request whose Host header is not loopback on this server's own
  /// port. A rebinding attack sends `Host: evil.tld`, so this is the layer that
  /// makes the browser treat the response as same-origin.
  bool _isAllowedHost(HttpRequest request, int port) {
    final raw = request.headers.value(HttpHeaders.hostHeader);
    if (raw == null || raw.isEmpty) return false;

    final trimmed = raw.trim();
    final separator = trimmed.lastIndexOf(':');
    final hostname = (separator == -1 ? trimmed : trimmed.substring(0, separator))
        .toLowerCase();
    final hostPort = separator == -1 ? null : int.tryParse(trimmed.substring(separator + 1));

    if (hostPort != port) return false;
    return _loopbackHosts.contains(hostname);
  }

  /// Refuses cross-origin requests outright. Omitting the CORS header would be
  /// enough to stop `fetch`, but refusing is unambiguous and also covers the
  /// preflight and simple-request shapes we do not enumerate here.
  bool _isAllowedOrigin(HttpRequest request, int port) =>
      isLoopbackHttpOrigin(request.headers.value(_originHeader), port);

  /// Cookie-based check; the query-parameter path is the bootstrap in
  /// [_bootstrap], which runs only for the very first request.
  bool _hasValidCookie(HttpRequest request, String token) {
    for (final cookie in request.cookies) {
      if (cookie.name == _cookieName && constantTimeEquals(cookie.value, token)) {
        return true;
      }
    }
    return false;
  }

  /// One-time bootstrap. The query token is the only form of authorisation the
  /// first request can present, since a fresh browser has no cookie yet. It is
  /// consumed immediately: the cookie (HttpOnly, so `document.cookie` cannot
  /// read it) is set and the response redirects to the same path without `bct`,
  /// so the page's own URL — `location.search`, history, `Referer` — never
  /// carries the token.
  ///
  /// The target is built only from the request path and remaining query
  /// parameters, so it is always a relative redirect to this same server and
  /// cannot point at another host.
  Future<void> _bootstrap(HttpRequest request, String token) async {
    final response = request.response;
    final cookie = Cookie(_cookieName, token)
      ..path = '/'
      ..httpOnly = true
      ..sameSite = SameSite.strict;
    response.cookies.add(cookie);

    final params = Map.of(request.uri.queryParameters)..remove(_cookieName);
    var path = request.uri.path;
    if (!path.startsWith('/')) path = '/$path';
    response.statusCode = HttpStatus.found;
    response.headers.set(
      HttpHeaders.locationHeader,
      params.isEmpty ? path : Uri(path: path, queryParameters: params).toString(),
    );
    await response.close();
  }

  /// The base policy plus two per-server additions: the live server's
  /// WebSocket origin for `connect-src`, and the response nonce for
  /// `script-src` so the app-injected reload client is the single inline
  /// script the policy admits.
  String _policy({required int port, String? nonce}) {
    var policy = _basePolicy;
    if (transformHtml != null) {
      policy = policy.replaceFirst(
        "connect-src 'self'",
        "connect-src 'self' ws://127.0.0.1:$port",
      );
    }
    if (nonce != null) {
      policy = policy.replaceFirst(
        "script-src 'self'",
        "script-src 'self' 'nonce-$nonce'",
      );
    }
    return policy;
  }

  String _nonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Compares without an early return so the running time does not reveal how
  /// much of the token matched. Shared with the live-reload WebSocket upgrade.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

/// Resolves a request path to a real regular file inside the root, or null if
  /// it escapes, does not exist, or is not a plain file.
  ///
  /// `request.uri.path` is already percent-decoded by `Uri`, so it must not be
  /// decoded again — doing so corrupts filenames containing `%` and turns a
  /// stray `%` into a 500.
  Future<File?> _resolveTarget(String urlPath) async {
    var rel = urlPath;
    if (rel.startsWith('/')) rel = rel.substring(1);
    if (rel.isEmpty) rel = 'index.html';
    if (rel.contains('\u0000')) return null;

    final rootAbs = p.normalize(p.absolute(rootPath));
    final candidate = p.normalize(p.join(rootAbs, rel));
    if (candidate != rootAbs && !p.isWithin(rootAbs, candidate)) return null;

    // The previewed page is same-origin with this server, so it can `fetch`
    // anything the server will serve. Dotfiles are where a workspace keeps its
    // secret material — `.env`, `.git/`, `.npmrc` — and no preview needs them.
    // Without this, opening an HTML file from an untrusted clone let that page
    // read every adjacent project's `.env` and send it out through a link the
    // app hands to the system browser.
    final within = p.relative(candidate, from: rootAbs);
    if (within != '.' &&
        within.split(p.separator).any((segment) => segment.startsWith('.'))) {
      return null;
    }

    final type = FileSystemEntity.typeSync(candidate, followLinks: false);
    if (type != FileSystemEntityType.file) return null;

    // Follow symlinks and re-check, so a link inside the workspace cannot point
    // at app-private storage outside it.
    final realRoot = await Directory(rootPath).resolveSymbolicLinks();
    final real = await File(candidate).resolveSymbolicLinks();
    if (real != realRoot && !p.isWithin(realRoot, real)) return null;

    return File(real);
  }

  Future<void> _fail(HttpRequest request, int status) async {
    try {
      request.response.statusCode = status;
      await request.response.close();
    } catch (_) {}
  }
}

String mimeFor(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'html' || 'htm' => 'text/html; charset=utf-8',
    'css' => 'text/css; charset=utf-8',
    'js' || 'mjs' => 'text/javascript; charset=utf-8',
    'json' => 'application/json',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'svg' => 'image/svg+xml',
    'webp' => 'image/webp',
    'ico' => 'image/x-icon',
    'woff' => 'font/woff',
    'woff2' => 'font/woff2',
    'ttf' => 'font/ttf',
    'txt' || 'md' => 'text/plain; charset=utf-8',
    'wasm' => 'application/wasm',
    _ => 'application/octet-stream',
  };
}