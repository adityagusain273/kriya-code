/// What the preview WebView should do with a navigation request.
enum PreviewNavigation {
  /// Load it inside the preview.
  navigate,

  /// Do not load it here, but let the system browser have it.
  external,

  /// Refuse it outright.
  block,
}

/// Decides navigation inside the preview WebView.
///
/// The preview shows `http://127.0.0.1:<port>` served from the workspace. Before
/// this policy existed every off-origin request was prevented, which made
/// Supabase and Firebase sign-in impossible: OAuth starts by navigating to the
/// provider and then back to the local redirect URL, and the first hop was
/// killed. Cloud backends are now trusted in-frame (their SDK also talks to them
/// with XHR, but a redirect-based flow needs the navigation), and everything
/// else off-origin is handed to the real browser rather than rendered in a frame
/// that looks like local code.
class PreviewNavigationPolicy {
  final Uri origin;

  const PreviewNavigationPolicy(this.origin);

  /// Hosts an OAuth round-trip passes through, plus the BaaS APIs a previewed
  /// app is expected to call.
  static const trustedHostSuffixes = [
    '.supabase.co',
    '.supabase.in',
    '.firebaseapp.com',
    '.web.app',
    '.google.com', // accounts.google.com
    '.googleapis.com',
    '.github.com',
    '.githubusercontent.com',
    '.microsoftonline.com',
    '.auth0.com',
  ];

  /// `intent://` is deliberately absent: it can start arbitrary activities, and
  /// a previewed page is not trusted to do that.
  static const _externalSchemes = {'mailto', 'tel'};

  bool isSameOrigin(Uri uri) =>
      uri.scheme == origin.scheme && uri.host == origin.host && uri.port == origin.port;

  bool isTrustedHost(String host) {
    final h = host.toLowerCase();
    return trustedHostSuffixes.any((suffix) => h == suffix.substring(1) || h.endsWith(suffix));
  }

  PreviewNavigation decide(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return PreviewNavigation.block;

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      if (isSameOrigin(uri) || isTrustedHost(uri.host)) return PreviewNavigation.navigate;
      return PreviewNavigation.external;
    }
    if (_externalSchemes.contains(scheme)) return PreviewNavigation.external;
    return PreviewNavigation.block;
  }
}
