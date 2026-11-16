import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/all.dart';

/// A contiguous slice of the buffer rendered with one token class.
///
/// Highlighting is flattened to these runs so the editor can rebuild a span
/// without walking a node tree, and so a run can be spliced when the buffer
/// changes before the next tokenization finishes.
@immutable
class HighlightRun {
  final int start;
  final int end;
  final String? className;

  const HighlightRun(this.start, this.end, this.className);

  @override
  String toString() => 'HighlightRun($start, $end, $className)';
}

const _openingBrackets = {'(', '[', '{'};
final _bracketPattern = RegExp(r'[\[\]\(\)\{\}]');

/// Flattens one highlight.js node tree into runs covering [text].
///
/// Bracket colourisation is folded in here: the old node-tree rewrite ran on
/// every repaint, which meant a second pass over the whole document each time
/// the caret moved. Classes match the previous `bracket-1`…`bracket-8` scheme.
///
/// Returns null when the tree does not cover [text], which would produce a span
/// whose offsets do not match the buffer (caret and IME break in that case).
List<HighlightRun>? buildHighlightRuns(List<Node>? nodes, String text) {
  if (nodes == null) return null;
  final runs = <HighlightRun>[];
  var offset = 0;
  var bracketDepth = 0;

  void walk(Node node, String? inheritedClass, bool inLiteral) {
    final className = node.className ?? inheritedClass;
    final literal =
        inLiteral || className == 'string' || className == 'comment';
    final value = node.value;

    if (value != null && value.isNotEmpty) {
      final start = offset;
      offset += value.length;

      if (literal) {
        _appendRun(runs, start, offset, className);
      } else {
        var cursor = 0;
        for (final match in _bracketPattern.allMatches(value)) {
          if (match.start > cursor) {
            _appendRun(runs, start + cursor, start + match.start, className);
          }
          final bracket = match.group(0)!;
          if (_openingBrackets.contains(bracket)) {
            bracketDepth++;
            _appendRun(
              runs,
              start + match.start,
              start + match.end,
              'bracket-${((bracketDepth - 1) % 8) + 1}',
            );
          } else {
            final depth = bracketDepth > 0 ? bracketDepth : 1;
            _appendRun(
              runs,
              start + match.start,
              start + match.end,
              'bracket-${((depth - 1) % 8) + 1}',
            );
            if (bracketDepth > 0) bracketDepth--;
          }
          cursor = match.end;
        }
        if (cursor < value.length) {
          _appendRun(runs, start + cursor, offset, className);
        }
      }
    }

    for (final child in node.children ?? const <Node>[]) {
      walk(child, className, literal);
    }
  }

  for (final node in nodes) {
    walk(node, null, false);
  }

  if (offset != text.length) return null;
  if (text.isNotEmpty) {
    _appendRun(runs, runs.isEmpty ? 0 : runs.last.end, text.length, null);
  }
  return runs;
}

/// Re-anchors [runs] (which describe [oldText]) onto [newText].
///
/// The common prefix and suffix keep their colours, so a keystroke does not
/// blank the whole document for the debounce window. Only the edited middle is
/// approximated with the class at the caret and corrected when the async pass
/// lands.
List<HighlightRun> spliceHighlightRuns(
  List<HighlightRun> runs,
  String oldText,
  String newText,
) {
  if (identical(oldText, newText) || oldText == newText) return runs;

  final oldLength = oldText.length;
  final newLength = newText.length;
  final maxPrefix = math.min(oldLength, newLength);
  var prefix = 0;
  while (prefix < maxPrefix &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }

  var suffix = 0;
  while (suffix < oldLength - prefix &&
      suffix < newLength - prefix &&
      oldText.codeUnitAt(oldLength - 1 - suffix) ==
          newText.codeUnitAt(newLength - 1 - suffix)) {
    suffix++;
  }

  final oldChangeEnd = oldLength - suffix;
  final newChangeEnd = newLength - suffix;
  final delta = newLength - oldLength;

  String? insertedClass;
  if (runs.isNotEmpty) {
    final probe = prefix > 0 ? prefix - 1 : 0;
    for (final run in runs) {
      if (probe >= run.start && probe < run.end) {
        insertedClass = run.className;
        break;
      }
      if (run.start > probe) break;
    }
  }

  final result = <HighlightRun>[];
  for (final run in runs) {
    if (run.start < prefix) {
      _appendRun(result, run.start, math.min(run.end, prefix), run.className);
    }
  }
  if (newChangeEnd > prefix) {
    _appendRun(result, prefix, newChangeEnd, insertedClass);
  }
  for (final run in runs) {
    if (run.end > oldChangeEnd) {
      _appendRun(
        result,
        math.max(run.start, oldChangeEnd) + delta,
        run.end + delta,
        run.className,
      );
    }
  }

  return _covers(result, newLength) ? result : _plainRuns(newLength);
}

/// Appends without leaving a hole: any uncovered slice before [start] becomes a
/// plain run, so the span always covers the whole buffer.
void _appendRun(
  List<HighlightRun> runs,
  int start,
  int end,
  String? className,
) {
  if (end <= start) return;
  final covered = runs.isEmpty ? 0 : runs.last.end;
  final from = start < covered ? covered : start;
  if (from >= end) return;
  if (from > covered) _appendRun(runs, covered, from, null);

  final tail = runs.isEmpty ? null : runs.last;
  if (tail != null && tail.end == from && tail.className == className) {
    runs[runs.length - 1] = HighlightRun(tail.start, end, className);
  } else {
    runs.add(HighlightRun(from, end, className));
  }
}

bool _covers(List<HighlightRun> runs, int length) {
  var cursor = 0;
  for (final run in runs) {
    if (run.start != cursor || run.end <= run.start) return false;
    cursor = run.end;
  }
  return cursor == length;
}

List<HighlightRun> _plainRuns(int length) =>
    length == 0 ? const [] : [HighlightRun(0, length, null)];

/// Tokenizes on a worker isolate and keeps a content-hash LRU.
///
/// One long-lived isolate is used so a grammar is compiled once, not once per
/// parse. Requests are keyed by grammar and content, so switching to a tab whose
/// buffer was already highlighted resolves from the cache without a round trip.
class AsyncHighlighter {
  AsyncHighlighter();

  static final AsyncHighlighter instance = AsyncHighlighter();

  static const _cacheLimit = 12;
  // A pathological minified file can produce tens of thousands of one-character
  // runs; caching those would cost more memory than the re-parse saves.
  static const _maxCachedRuns = 8000;

  final _cache = <int, List<HighlightRun>>{};
  final _inflight = <int, Future<List<HighlightRun>?>>{};
  final _grammarKeys = <Mode, String?>{};

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _starting;
  var _sequence = 0;
  var _closed = false;
  final _jobs = <int, Completer<List<HighlightRun>?>>{};

  Future<List<HighlightRun>?> highlight(String text, Mode mode) {
    if (_closed) return Future.value(null);
    if (text.isEmpty) return Future.value(const []);
    final grammar = _grammarKey(mode);
    if (grammar == null) return Future.value(null);
    if (grammar == 'plaintext') {
      return Future.value(text.isEmpty ? const [] : _plainRuns(text.length));
    }

    final key = Object.hash(grammar, text.length, _hash(text));
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }

    final running = _inflight[key];
    if (running != null) return running;

    final future = _dispatch(text, grammar, key);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  String? _grammarKey(Mode mode) {
    if (_grammarKeys.containsKey(mode)) return _grammarKeys[mode];
    String? key;
    for (final entry in allLanguages.entries) {
      if (identical(entry.value, mode)) {
        key = entry.key;
        break;
      }
    }
    _grammarKeys[mode] = key;
    return key;
  }

  Future<List<HighlightRun>?> _dispatch(
    String text,
    String grammar,
    int cacheKey,
  ) async {
    try {
      await _ensureWorker();
      final sequence = ++_sequence;
      final completer = Completer<List<HighlightRun>?>();
      _jobs[sequence] = completer;
      _toWorker!.send(<Object>[sequence, text, grammar]);
      final runs = await completer.future;
      if (_closed) return null;
      if (runs != null && _covers(runs, text.length)) {
        if (runs.length <= _maxCachedRuns) {
          _cache[cacheKey] = runs;
          while (_cache.length > _cacheLimit) {
            _cache.remove(_cache.keys.first);
          }
        }
        return runs;
      }
      return null;
    } catch (e) {
      debugPrint('AsyncHighlighter: $e');
      return null;
    }
  }

  Future<void> _ensureWorker() {
    if (_toWorker != null) return Future.value();
    final starting = _starting;
    if (starting != null) return starting;

    final completer = Completer<void>();
    _starting = completer.future;

    final port = ReceivePort();
    _fromWorker = port;
    _subscription = port.listen((message) {
      if (message is SendPort) {
        _toWorker = message;
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (message is! List || message.length < 2) return;
      final sequence = message[0] as int;
      final job = _jobs.remove(sequence);
      if (job == null) return;
      final runs = (message[1] as List?)?.cast<HighlightRun>();
      job.complete(runs);
    });

    Isolate.spawn(
      _highlightWorker,
      port.sendPort,
      debugName: 'bcode-highlighter',
    ).then((isolate) {
      _isolate = isolate;
    }).catchError((Object e) {
      debugPrint('AsyncHighlighter: worker failed to start: $e');
      if (!completer.isCompleted) completer.completeError(e);
      _starting = null;
    });

    return completer.future;
  }

  /// Stops the worker. Only used by tests; the app keeps one for its lifetime.
  Future<void> close() async {
    _closed = true;
    for (final job in _jobs.values) {
      if (!job.isCompleted) job.complete(null);
    }
    _jobs.clear();
    await _subscription?.cancel();
    _subscription = null;
    _fromWorker?.close();
    _fromWorker = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _starting = null;
    _cache.clear();
  }

  static int _hash(String text) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < text.length; i++) {
      hash = ((hash ^ text.codeUnitAt(i)) * 0x01000193) & 0x3fffffff;
    }
    return hash;
  }
}

@pragma('vm:entry-point')
void _highlightWorker(SendPort reply) {
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);

  inbox.listen((message) {
    if (message is! List || message.length < 3) return;
    final sequence = message[0] as int;
    final text = message[1] as String;
    final grammar = message[2] as String;

    List<HighlightRun>? runs;
    try {
      final result = hl.highlight.parse(text, language: grammar);
      runs = buildHighlightRuns(result.nodes, text);
    } catch (_) {
      runs = null;
    }
    reply.send(<Object?>[sequence, runs]);
  });
}
