import 'package:flutter/material.dart';

/// Wraps the editor so a two-finger pinch dynamically scales the font size,
/// matching the Acode pinch-to-zoom extension architecture.
///
/// Features:
/// - Direct font-size scaling (text reflows naturally, line numbers align)
/// - Threshold and move confirmation to prevent accidental zooms while scrolling
/// - Throttled preview updates during gestures
/// - Clamped font limits (min 8.0, max 64.0)
/// - Persists directly to settings upon gesture completion (onZoomEnd)
/// - Reset to default on chip tap
class BCodeZoomView extends StatefulWidget {
  final Widget child;
  final double fontSize;
  final ValueChanged<double>? onFontSizePreview;
  final ValueChanged<double>? onFontSizeCommit;
  final double minFontSize;
  final double maxFontSize;

  const BCodeZoomView({
    super.key,
    required this.child,
    required this.fontSize,
    this.onFontSizePreview,
    this.onFontSizeCommit,
    this.minFontSize = 8.0,
    this.maxFontSize = 64.0,
  });

  @override
  State<BCodeZoomView> createState() => _BCodeZoomViewState();
}

class _BCodeZoomViewState extends State<BCodeZoomView> {
  final Map<int, Offset> _pointers = {};
  double _startDistance = 0;
  double _startFontSize = 14.0;
  double _currentFontSize = 14.0;
  bool _pinching = false;
  bool _moved = false;
  int _lastUpdateMs = 0;

  static const double _moveThreshold = 10.0;
  static const int _throttleMs = 30;

  @override
  void initState() {
    super.initState();
    _currentFontSize = widget.fontSize;
  }

  @override
  void didUpdateWidget(BCodeZoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pinching && widget.fontSize != oldWidget.fontSize) {
      _currentFontSize = widget.fontSize;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      final positions = _pointers.values.toList();
      _startDistance = (positions[0] - positions[1]).distance;
      _startFontSize = widget.fontSize;
      _currentFontSize = widget.fontSize;
      _pinching = true;
      _moved = false;
      _lastUpdateMs = 0;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;

    if (!_pinching || _pointers.length != 2 || _startDistance <= 0) return;

    final positions = _pointers.values.toList();
    final currentDistance = (positions[0] - positions[1]).distance;
    final delta = currentDistance - _startDistance;

    if (!_moved) {
      if (delta.abs() < _moveThreshold) {
        return;
      }
      _moved = true;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUpdateMs < _throttleMs) {
      return;
    }
    _lastUpdateMs = now;

    final nextSize = (_startFontSize * (currentDistance / _startDistance))
        .clamp(widget.minFontSize, widget.maxFontSize);

    if ((nextSize - _currentFontSize).abs() > 0.2) {
      setState(() => _currentFontSize = nextSize);
      widget.onFontSizePreview?.call(nextSize);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.length < 2) {
      _pinching = false;
      if (_moved) {
        widget.onFontSizeCommit?.call(_currentFontSize);
      }
      _startDistance = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultSize = 14.0;
    final ratio = _currentFontSize / defaultSize;
    final showBadge = (ratio - 1.0).abs() > 0.08;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: Stack(
        children: [
          widget.child,
          if (showBadge)
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () {
                    setState(() => _currentFontSize = defaultSize);
                    widget.onFontSizePreview?.call(defaultSize);
                    widget.onFontSizeCommit?.call(defaultSize);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${(ratio * 100).round()}% (${_currentFontSize.round()}pt)',
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
