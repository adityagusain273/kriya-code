import 'dart:async';

import 'package:flutter/services.dart';

/// One chunk of output from a running program.
class ExecEvent {
  final String runId;

  /// `stdout` or `stderr`.
  final String stream;
  final String data;

  const ExecEvent({
    required this.runId,
    required this.stream,
    required this.data,
  });
}

/// Turns arbitrary output chunks into whole lines.
///
/// A process can split a line across reads, so the tail is held until the next
/// chunk or [flush]. Without this the console gained a blank line at every
/// chunk boundary.
class LineCollector {
  final _buffer = StringBuffer();

  /// Complete lines in [chunk]; the unfinished tail stays buffered.
  List<String> add(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final cut = text.lastIndexOf('\n');
    if (cut < 0) return const [];
    _buffer
      ..clear()
      ..write(text.substring(cut + 1));
    return text.substring(0, cut).split('\n');
  }

  /// Returns the unfinished tail, if any, and clears it.
  List<String> flush() {
    final text = _buffer.toString();
    _buffer.clear();
    return text.isEmpty ? const [] : [text];
  }

  void clear() => _buffer.clear();
}

/// Bridges the native run-event channel to Dart.
///
/// The native side captures stdout/stderr on two reader threads and posts each
/// chunk here as it arrives, so the console updates while the program runs
/// instead of only after it exits.
class ExecEvents {
  ExecEvents._();

  static final ExecEvents instance = ExecEvents._();
  static const _channel = EventChannel('bcode.exec/stream');

  final _controller = StreamController<ExecEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  Stream<ExecEvent> get stream => _controller.stream;

  void ensureListening() {
    if (_subscription != null) return;
    _subscription = _channel.receiveBroadcastStream().listen(
      (raw) {
        if (raw is! Map) return;
        final runId = raw['runId'];
        final stream = raw['stream'];
        final data = raw['data'];
        if (runId is! String || stream is! String || data is! String) return;
        _controller.add(ExecEvent(runId: runId, stream: stream, data: data));
      },
      onError: (Object _) {},
    );
  }
}
