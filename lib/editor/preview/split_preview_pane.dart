import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'preview_navigation.dart';

class SplitPreviewPane extends StatefulWidget {
  final String baseUrl;
  final String relativePath;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;

  const SplitPreviewPane({
    super.key,
    required this.baseUrl,
    required this.relativePath,
    required this.title,
    this.onClose,
    this.onExpand,
  });

  @override
  State<SplitPreviewPane> createState() => SplitPreviewPaneState();
}

class SplitPreviewPaneState extends State<SplitPreviewPane> {
  late final WebViewController _controller;
  late Uri _origin;
  late PreviewNavigationPolicy _policy;

  @override
  void initState() {
    super.initState();
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
    _loadTargetUrl();
  }

  @override
  void didUpdateWidget(SplitPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.relativePath != widget.relativePath) {
      _origin = Uri.parse(widget.baseUrl);
      _policy = PreviewNavigationPolicy(_origin);
      _loadTargetUrl();
    }
  }

  void _loadTargetUrl() {
    final rel = widget.relativePath.isEmpty
        ? ''
        : (widget.relativePath.startsWith('/')
            ? widget.relativePath.substring(1)
            : widget.relativePath);
    final target = rel.isEmpty ? widget.baseUrl : '${widget.baseUrl}/$rel';
    _controller.loadRequest(Uri.parse(target));
  }

  void reload() {
    _controller.reload();
  }

  void _hardenWebView(WebViewController controller) {
    if (kIsWeb) return;
    if (Platform.isAndroid && controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setAllowFileAccess(false);
      android.setAllowContentAccess(false);
    }
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181818),
      child: Column(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Preview',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.title.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: 'Reload preview',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: reload,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 15),
                  tooltip: 'Open in system browser',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: () => _openExternally(widget.baseUrl),
                ),
                if (widget.onExpand != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.fullscreen, size: 18),
                    tooltip: 'Full screen preview',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: widget.onExpand,
                  ),
                ],
                if (widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Close preview',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: widget.onClose,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
