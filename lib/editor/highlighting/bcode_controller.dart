import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart';

import '../../lsp/diagnostics.dart';
import 'async_highlighter.dart';
import 'diagnostic_highlight_builder.dart';

typedef HighlightRequest = Future<List<HighlightRun>?> Function(
  String text,
  Mode mode,
);

class BCodeController extends CodeController {
  // ignore: use_super_parameters
  BCodeController({
    String? text,
    Mode? language,
    EditorParams params = const EditorParams(),
    HighlightRequest? highlightRequest,
  })  : _request = highlightRequest ?? AsyncHighlighter.instance.highlight,
        super(text: text, language: null, params: params) {
    _seenText = this.text;
    _large = isLargeBuffer(this.text);
    addListener(_onChanged);
    this.language = language;
  }

  /// Re-tokenises after the user stops typing. Long enough that a burst of
  /// keystrokes costs one pass, short enough that colours catch up before the
  /// next thought.
  static const highlightDebounce = Duration(milliseconds: 180);

  /// Above this size a buffer renders as plain text.
  ///
  /// A 5,000-line file tokenises to ~45,000 runs, and rebuilding that TextSpan
  /// on every keystroke costs ~20 s on a laptop-class CPU; a phone is slower.
  /// Line count is a cheap predictor measured on the same shape of file.
  static const largeFileLineThreshold = 2000;
  static const largeFileCharThreshold = 60 * 1024;

  /// Whether [text] is too large to colour. Kept as a pure function so the
  /// threshold can be tested without a widget.
  static bool isLargeBuffer(String text) =>
      text.length > largeFileCharThreshold ||
      _countLines(text) > largeFileLineThreshold;

  static int _countLines(String text) {
    var lines = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) lines++;
    }
    return lines;
  }

  /// True when this buffer is too large to colour, so it renders plain.
  bool get plainTextFallback => _large;

  bool _large = false;

  final HighlightRequest _request;

  Mode? _mode;
  String _seenText = '';
  Timer? _debounce;

  /// Runs for the buffer at [_runsVersion]. Rendering only trusts them while
  /// that matches [_textVersion], so a stale tree can never be shown against
  /// newer text.
  List<HighlightRun>? _runs;
  String _runsText = '';
  int _runsVersion = 0;
  int _textVersion = 0;

  List<Diagnostic> _diagnostics = const [];
  bool _disposed = false;
  int _renderVersion = 0;

  TextSpan? _cachedSpan;
  String? _cachedText;
  TextStyle? _cachedStyle;
  CodeThemeData? _cachedTheme;
  List<Diagnostic>? _cachedDiagnostics;
  int _cachedVersion = -1;

  /// Tokenisation no longer runs inside the package: answering null keeps
  /// `CodeController` building only line metadata, and keeps the per-keystroke
  /// `Code` work linear instead of re-parsing. The grammar lives in [_mode] for
  /// the async request.
  @override
  Mode? get language => null;

  @override
  set language(Mode? mode) {
    if (identical(mode, _mode)) return;
    _mode = mode;
    // The package's inline completion popup is independent of tokenisation.
    autocompleter.mode = mode;
    _runs = null;
    _runsVersion = _textVersion;
    _renderVersion++;
    _scheduleHighlight(immediate: true);
    notifyListeners();
  }

  /// Keeps the package's own language setter from re-enabling synchronous
  /// tokenisation if it is ever called directly.
  @override
  void setLanguage(Mode? language, {required AbstractAnalyzer analyzer}) {
    if (identical(language, _mode)) return;
    this.language = language;
  }

  List<Diagnostic> get diagnostics => _diagnostics;

  set diagnostics(List<Diagnostic> val) {
    if (_diagnostics != val) {
      _diagnostics = val;
      notifyListeners();
    }
  }

  /// Runs currently backing the rendered span. Empty until tokenisation lands.
  @visibleForTesting
  List<HighlightRun>? get highlightRuns =>
      _runsVersion == _textVersion ? _runs : null;

  /// Cancels the debounce and tokenises now. Tests use this to await colours;
  /// production relies on the timer.
  @visibleForTesting
  Future<void> settleHighlight() async {
    _debounce?.cancel();
    _debounce = null;
    final mode = _mode;
    if (mode == null) return;
    await _runHighlight(text, mode);
  }

  /// Pairs whose closing half the editor inserts automatically, mapped to the
  /// character the user has to type to move past it.
  static const _closers = <String, String>{
    ')': '(',
    ']': '[',
    '}': '{',
    '"': '"',
    "'": "'",
    '`': '`',
  };

  /// Steps over an auto-inserted closing character rather than duplicating it.
  ///
  /// Typing `(` already produces `()` with the caret between them. Typing the `)`
  /// next is the natural keystroke, and without this it produced `())` — unbalanced
  /// code that then failed to run, which is a poor first experience on a phone.
  ///
  /// Done here rather than through the editor's [CodeModifier] hook because that
  /// table is keyed by character: registering a handler for `"` replaces the
  /// package's own quote insertion, and adding one for `)` ran into assumptions in
  /// the package's read-only range check that a shrinking edit violates.
  @override
  set value(TextEditingValue newValue) {
    final adjusted = _stepOverClosingCharacter(newValue);
    super.value = adjusted ?? newValue;
  }

  TextEditingValue? _stepOverClosingCharacter(TextEditingValue incoming) {
    final current = super.value;
    if (incoming.text.length != current.text.length + 1) return null;
    final sel = current.selection;
    if (!sel.isCollapsed || sel.start < 0) return null;
    if (sel.start >= current.text.length) return null;

    // The character that was just typed sits immediately before the caret in the
    // incoming text; the caret itself has already moved past it.
    final typed = incoming.text[sel.start];
    final opener = _closers[typed];
    if (opener == null) return null;

    // There must be an identical closer already sitting at the caret, and it must
    // belong to a pair that is still open. Otherwise this keystroke is genuine,
    // such as the bracket in `print(1) + 2)`.
    if (current.text[sel.start] != typed) return null;
    if (!_isPairPending(current.text, sel.start, opener, typed)) return null;

    return TextEditingValue(
      text: current.text,
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  /// Whether a pair opened by [opener] is still open before [caret].
  static bool _isPairPending(
    String text,
    int caret,
    String opener,
    String closer,
  ) {
    var open = 0;
    var close = 0;
    for (var i = 0; i < caret; i++) {
      final ch = text[i];
      if (ch == opener) open++;
      // Quotes are their own opener and closer, so they must not cancel themselves
      // out or an empty string would look unclosed.
      if (ch == closer && closer != opener) close++;
    }
    return open > close;
  }

  void _onChanged() {
    if (_disposed) return;
    final current = text;
    if (identical(current, _seenText)) return;
    _seenText = current;
    _textVersion++;

    final runs = _runs;
    _large = isLargeBuffer(current);
    if (_large) {
      // Drop the runs: rebuilding a 45,000-span TextSpan is what freezes the
      // UI, so a buffer that crosses the threshold stops being coloured.
      if (runs != null) {
        _runs = null;
        _renderVersion++;
      }
      _runsVersion = _textVersion;
    } else if (runs != null && _runsVersion == _textVersion - 1) {
      _runs = spliceHighlightRuns(runs, _runsText, current);
      _runsText = current;
      _runsVersion = _textVersion;
      _renderVersion++;
    }
    _scheduleHighlight();
  }

  void _scheduleHighlight({bool immediate = false}) {
    _debounce?.cancel();
    final mode = _mode;
    if (mode == null || plainTextFallback) return;

    final snapshot = text;
    _debounce = Timer(
      immediate ? Duration.zero : highlightDebounce,
      () => unawaited(_runHighlight(snapshot, mode)),
    );
  }

  Future<void> _runHighlight(String snapshot, Mode mode) async {
    if (plainTextFallback) return;
    List<HighlightRun>? runs;
    try {
      runs = await _request(snapshot, mode);
    } catch (e) {
      debugPrint('BCodeController: highlight failed: $e');
      return;
    }
    if (_disposed || !identical(_mode, mode) || text != snapshot) return;

    _runs = runs;
    _runsText = snapshot;
    _runsVersion = _textVersion;
    _renderVersion++;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final current = text;
    final theme = CodeTheme.of(context);

    if (_cachedSpan != null &&
        identical(current, _cachedText) &&
        _cachedVersion == _renderVersion &&
        _cachedStyle == style &&
        identical(theme, _cachedTheme) &&
        identical(_diagnostics, _cachedDiagnostics)) {
      return _cachedSpan!;
    }

    final runs = _runsVersion == _textVersion ? _runs : null;
    final textLength = current.length;
    final valid =
        runs != null && runs.isNotEmpty && _coversBuffer(runs, textLength);

    TextSpan span;
    if (!valid) {
      span = TextSpan(text: current, style: style);
    } else {
      final styles = theme?.styles;
      final children = <InlineSpan>[];
      for (final run in runs) {
        children.add(TextSpan(
          text: current.substring(run.start, run.end),
          style: styles?[run.className],
        ));
      }
      span = TextSpan(style: style, children: children);
    }

    if (_diagnostics.isNotEmpty) {
      span = DiagnosticHighlightedBuilder(
        diagnostics: _diagnostics,
        textLength: current.length,
        rootStyle: style,
        textSpan: span,
      ).build();
    }

    _cachedSpan = span;
    _cachedText = current;
    _cachedStyle = style;
    _cachedTheme = theme;
    _cachedDiagnostics = _diagnostics;
    _cachedVersion = _renderVersion;
    return span;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    removeListener(_onChanged);
    super.dispose();
  }

  /// Guards the caret: a span must cover every character exactly once, or Flutter
  /// maps offsets through spans that do not exist and the selection lands in the
  /// wrong place.
  static bool _coversBuffer(List<HighlightRun> runs, int length) {
    var cursor = 0;
    for (final run in runs) {
      if (run.start != cursor || run.end <= run.start) return false;
      cursor = run.end;
    }
    return cursor == length;
  }
}
