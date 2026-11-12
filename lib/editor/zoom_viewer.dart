import 'package:flutter/material.dart';

/// Wraps the editor so a two-finger pinch changes the code size.
///
/// The zoom factor is owned by the caller and applied to the editor font size,
/// so text reflows and the caret keeps landing where it is tapped. Transforming
/// the painted editor instead (as an InteractiveViewer does) moved the whole
/// panel around without ever feeling like the code zoomed.
///
/// Raw pointer events are used deliberately: a ScaleGestureRecognizer competes
/// in the gesture arena and would steal the editor's one-finger scroll and
/// text selection. A Listener observes the same pointers without claiming them.
class BCodeZoomView extends StatefulWidget {
  final Widget child;
  final double scale;
  final ValueChanged<double>? onScaleChanged;
  final double minScale;
  final double maxScale;

  const BCodeZoomView({
    super.key,
    required this.child,
    this.scale = 1.0,
    this.onScaleChanged,
    this.minScale = 0.5,
    this.maxScale = 3.0,
  });

  @override
  State<BCodeZoomView> createState() => _BCodeZoomViewState();
}

class _BCodeZoomViewState extends State<BCodeZoomView> {
  final Map<int, Offset> _pointers = {};
  double _startDistance = 0;
  double? _startScale;

  void _resetBaseline() {
    if (_pointers.length == 2) {
      final positions = _pointers.values.toList();
      _startDistance = (positions[0] - positions[1]).distance;
      _startScale = widget.scale;
    } else {
      _startDistance = 0;
      _startScale = null;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    _resetBaseline();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    final startScale = _startScale;
    if (_pointers.length != 2 || startScale == null || _startDistance <= 0) return;

    final positions = _pointers.values.toList();
    final distance = (positions[0] - positions[1]).distance;
    final next = (startScale * distance / _startDistance)
        .clamp(widget.minScale, widget.maxScale);
    widget.onScaleChanged?.call(next);
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    _resetBaseline();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: Stack(
        children: [
          widget.child,
          if ((widget.scale - 1.0).abs() > 0.02)
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () => widget.onScaleChanged?.call(1.0),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${(widget.scale * 100).round()}%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
