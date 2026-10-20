import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class PreviewPage extends StatefulWidget {
  final String baseUrl;
  final String relativePath;
  final String title;

  const PreviewPage({
    super.key,
    required this.baseUrl,
    required this.relativePath,
    required this.title,
  });

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final WebViewController _controller;
  late final Uri _origin;

  static const _blockedSchemes = {
    'file',
    'content',
    'data',
    'intent',
    'javascript',
    'ftp',
    'ws',
    'wss',
  };

  @override
  void initState() {
    super.initState();
    _origin = Uri.parse(widget.baseUrl);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _allowNavigation,
        onWebResourceError: (_) {},
        onPageFinished: (_) {
          if (mounted) setState(() {});
        },
      ));

    _hardenWebView(_controller);

    final rel = widget.relativePath.isEmpty
        ? ''
        : (widget.relativePath.startsWith('/')
            ? widget.relativePath.substring(1)
            : widget.relativePath);
    _controller.loadRequest(Uri.parse(rel.isEmpty ? widget.baseUrl : '${widget.baseUrl}/$rel'));
  }

  /// `allowFileAccess` defaults to true below API 30 and false from API 30.
  /// minSdk here is 24, so on older devices the default would let a previewed
  /// page navigate to `file:///data/data/com.bcode.editor/...` and have app
  /// storage rendered on screen. Set it explicitly rather than relying on the
  /// platform default.
  void _hardenWebView(WebViewController controller) {
    if (kIsWeb) return;
    if (Platform.isAndroid && controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setAllowFileAccess(false);
      android.setAllowContentAccess(false);
    }
  }

  NavigationDecision _allowNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    final scheme = uri.scheme.toLowerCase();
    if (_blockedSchemes.contains(scheme)) return NavigationDecision.prevent;
    if (scheme != 'http' && scheme != 'https') {
      return NavigationDecision.prevent;
    }

    if (uri.scheme == _origin.scheme &&
        uri.host == _origin.host &&
        uri.port == _origin.port) {
      return NavigationDecision.navigate;
    }

    // Off-origin navigation would turn this screen into a browser inside a
    // trusted-looking frame. Decline it.
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Preview — ${widget.title}',
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
