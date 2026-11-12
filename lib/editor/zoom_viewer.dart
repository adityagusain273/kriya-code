import 'package:flutter/material.dart';

/// Wraps the editor so it can be pinched to zoom.
///
/// Two problems had to be solved for this to work at all:
///
///  * **The content is a text field**, which installs its own gesture recognisers
///    for selection and scrolling. [InteractiveViewer] only sees a pinch if its
///    [ScaleGestureRecognizer] is allowed to claim the gesture arena, so the
///    recogniser is supplied explicitly instead of relying on the defaults.
///  * **Scaling a text field scales the text but not the layout around it.** The
///    content is laid out once and transformed, which keeps the caret and the
///    selection where the user expects them instead of re-flowing the whole
///    document on every frame.
///
/// [minScale] of 1 keeps the unzoomed appearance identical to having no viewer at
/// all, so enabling the extension changes nothing until the user pinches.
class BCodeZoomView extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;

  const BCodeZoomView({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 4.0,
  });

  @override
  State<BCodeZoomView> createState() => _BCodeZoomViewState();
}

class _BCodeZoomViewState extends State<BCodeZoomView> {
  final TransformationController _controller = TransformationController();

  /// Zoom currently applied, so the on-screen indicator can be shown and reset.
  double _scale = 1.0;

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
    }
  }

  void _reset() {
    _controller.value = Matrix4.identity();
    // setState will be called by _syncScale
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _controller,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          // By setting boundaryMargin to zero, we prevent the user from panning
          // the zoomed document off-screen (so it never "floats in the air").
          // Additionally, at scale 1.0, the child perfectly fits the viewport,
          // so InteractiveViewer won't steal single-finger pan gestures, allowing
          // the text field to scroll normally.
          boundaryMargin: EdgeInsets.zero,
          // We use Clip.hardEdge so that when the user zooms in, the scaled text
          // is properly contained within the editor's viewport and does not 
          // draw over the tab bar or app bar.
          clipBehavior: Clip.hardEdge,
          panEnabled: true,
          scaleEnabled: true,
          child: widget.child,
        ),
        if (_scale > 1.02)
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
    );
  }
}