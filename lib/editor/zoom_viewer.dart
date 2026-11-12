import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

/// Wraps the editor so the code can be pinched to zoom in and out,
/// while keeping line numbers fixed at their standard readable size in the gutter.
class BCodeZoomView extends StatefulWidget {
  final Widget child;
  final CodeController? controller;
  final bool showLineNumbers;
  final double fontSize;
  final String? fontFamily;
  final Color gutterBackground;
  final double minScale;
  final double maxScale;

  const BCodeZoomView({
    super.key,
    required this.child,
    this.controller,
    this.showLineNumbers = false,
    this.fontSize = 14.0,
    this.fontFamily,
    this.gutterBackground = Colors.transparent,
    this.minScale = 0.5,
    this.maxScale = 3.0,
  });

  @override
  State<BCodeZoomView> createState() => _BCodeZoomViewState();
}

class _BCodeZoomViewState extends State<BCodeZoomView> {
  final TransformationController _controller = TransformationController();

  /// Zoom currently applied, so the on-screen indicator can be shown and reset.
  double _scale = 1.0;
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScale);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncScale);
    _controller.dispose();
    super.dispose();
  }

  void _syncScale() {
    final nextScale = _controller.value.getMaxScaleOnAxis();
    if ((nextScale - _scale).abs() > 0.001) {
      _scale = nextScale;
      if (mounted) setState(() {});
    } else if (mounted) {
      setState(() {});
    }
  }

  void _reset() {
    _controller.value = Matrix4.identity();
  }

  double _calculateLineHeight() {
    final tp = TextPainter(
      text: TextSpan(
        text: '0',
        style: TextStyle(
          fontFamily: widget.fontFamily ?? 'monospace',
          fontSize: widget.fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.preferredLineHeight;
  }

  Widget _buildFixedGutter() {
    final controller = widget.controller;
    if (controller == null || !widget.showLineNumbers) {
      return const SizedBox.shrink();
    }

    final lineCount = controller.code.lines.length;
    final baseLineHeight = _calculateLineHeight();
    final lineHeight = baseLineHeight * _scale;
    final ty = _controller.value.getTranslation().y;
    final scrollY = _scrollOffset * _scale;
    final topPadding = 16.0 * _scale;

    return Container(
      width: 48,
      color: widget.gutterBackground,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge([controller, _controller]),
          builder: (context, _) {
            return Transform.translate(
              offset: Offset(0, ty - scrollY),
              child: Padding(
                padding: EdgeInsets.only(top: topPadding, bottom: topPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(lineCount, (index) {
                    return SizedBox(
                      height: lineHeight,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildFixedGutter(),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis == Axis.vertical) {
                    final newPixels = notification.metrics.pixels;
                    if ((newPixels - _scrollOffset).abs() > 0.5) {
                      _scrollOffset = newPixels;
                      if (mounted) setState(() {});
                    }
                  }
                  return false;
                },
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: widget.minScale,
                  maxScale: widget.maxScale,
                  boundaryMargin: const EdgeInsets.all(1000),
                  clipBehavior: Clip.hardEdge,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: widget.child,
                ),
              ),
              if ((_scale - 1.0).abs() > 0.02)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: _reset,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text(
                          '${(_scale * 100).round()}%',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
