import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/di.dart';
import '../../servers/server_monitor.dart';
import 'preview_navigation.dart';

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
  late final PreviewNavigationPolicy _policy;

  @override
  void initState() {
    super.initState();
    sl<ServerMonitor>().startPolling();
    _origin = Uri.parse(widget.baseUrl);
    _policy = PreviewNavigationPolicy(_origin);

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

  @override
  void dispose() {
    sl<ServerMonitor>().stopPolling();
    super.dispose();
  }

  NavigationDecision _allowNavigation(NavigationRequest request) {
    switch (_policy.decide(request.url)) {
      case PreviewNavigation.navigate:
        return NavigationDecision.navigate;
      case PreviewNavigation.external:
        unawaited(_openExternally(request.url));
        return NavigationDecision.prevent;
      case PreviewNavigation.block:
        return NavigationDecision.prevent;
    }
  }

  Future<void> _openExternally(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser, or the system refused the scheme. Staying on the preview is
      // the right fallback.
    }
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
