import 'package:flutter/material.dart';

class FindReplaceController extends ChangeNotifier {
  final TextEditingController source;
  String query = '';
  String replacement = '';
  bool caseSensitive = false;
  bool useRegex = false;
  bool wholeWord = false;
  int _currentIndex = -1;
  final List<Match> _matches = [];

  /// The buffer the current matches were computed against, or null when they are
  /// stale.
  ///
  /// `Match.start`/`Match.end` are offsets, so they only mean anything against the
  /// exact text they were computed from. The find bar can be closed while the user
  /// keeps typing and reopened afterwards, and nothing recomputed the offsets in
  /// between — pressing Replace then spliced the replacement in at the stale
  /// position and mangled the file. Recomputing is deferred rather than done per
  /// keystroke so an open find bar over a large buffer costs nothing while it is
  /// not being used.
  ///
  /// Keyed on the text rather than on "something changed": moving the caret, which
  /// the bar itself does after every match, leaves the offsets perfectly valid and
  /// must not throw them away.
  String? _matchedText;

  bool get _stale => _matchedText != source.text;

  FindReplaceController(this.source) {
    source.addListener(_onSourceChanged);
  }

  void _onSourceChanged() {
    if (!_stale) return;
    notifyListeners();
  }

  int get currentIndex {
    _ensureFresh();
    return _currentIndex;
  }

  int get matchCount {
    _ensureFresh();
    return _matches.length;
  }

  void _ensureFresh() {
    if (!_stale) return;
    _recompute();
  }

  void _recompute() {
    final text = source.text;
    _matchedText = text;
    _matches
      ..clear()
      ..addAll(_computeMatches(text));
    if (_matches.isEmpty) {
      _currentIndex = -1;
    } else if (_currentIndex >= _matches.length) {
      _currentIndex = _matches.length - 1;
    }
  }

  @override
  void dispose() {
    source.removeListener(_onSourceChanged);
    super.dispose();
  }

  List<Match> _computeMatches(String haystack) {
    if (query.isEmpty || haystack.isEmpty) return const [];
    try {
      String pattern;
      if (useRegex) {
        pattern = query;
      } else {
        pattern = RegExp.escape(query);
      }
      if (wholeWord && !useRegex) {
        pattern = r'\b' + pattern + r'\b';
      }
      final regex = RegExp(pattern, caseSensitive: caseSensitive, multiLine: true);
      return regex.allMatches(haystack).toList();
    } catch (_) {
      return const [];
    }
  }

  void search({bool jumpToFirst = false}) {
    _recompute();
    if (_matches.isEmpty) {
      _currentIndex = -1;
    } else {
      _currentIndex = jumpToFirst
          ? 0
          : (_currentIndex + 1).clamp(0, _matches.length - 1);
      _selectMatch();
    }
    notifyListeners();
  }

  void previous() {
    _ensureFresh();
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % _matches.length;
    if (_currentIndex < 0) _currentIndex = _matches.length - 1;
    _selectMatch();
    notifyListeners();
  }

  void next() {
    _ensureFresh();
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    _selectMatch();
    notifyListeners();
  }

  void replaceCurrent() {
    _ensureFresh();
    if (_currentIndex < 0 || _currentIndex >= _matches.length) return;
    final match = _matches[_currentIndex];
    final text = source.text;
    if (match.start < 0 || match.end > text.length || match.start > match.end) {
      search(jumpToFirst: true);
      return;
    }
    final updated = text.substring(0, match.start) +
        replacement +
        text.substring(match.end);
    source.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
          offset: (match.start + replacement.length).clamp(0, updated.length)),
    );
    search();
  }

  void replaceAll() {
    _ensureFresh();
    if (query.isEmpty || _matches.isEmpty) return;
    final matches = _computeMatches(source.text);
    if (matches.isEmpty) return;
    final buffer = StringBuffer();
    int lastEnd = 0;
    for (final match in matches) {
      buffer.write(source.text.substring(lastEnd, match.start));
      buffer.write(replacement);
      lastEnd = match.end;
    }
    buffer.write(source.text.substring(lastEnd));
    source.value = TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: 0),
    );
    search(jumpToFirst: true);
  }

  void _selectMatch() {
    if (_currentIndex < 0 || _currentIndex >= _matches.length) return;
    final match = _matches[_currentIndex];
    source.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }
}

class FindReplaceBar extends StatefulWidget {
  final FindReplaceController controller;

  const FindReplaceBar({super.key, required this.controller});

  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  bool showReplace = false;
  late final TextEditingController _queryField;
  late final TextEditingController _replaceField;

  @override
  void initState() {
    super.initState();
    _queryField = TextEditingController(text: widget.controller.query);
    _replaceField = TextEditingController(text: widget.controller.replacement);
  }

  @override
  void dispose() {
    _queryField.dispose();
    _replaceField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (_queryField.text != c.query) {
          _queryField.value = TextEditingValue(
            text: c.query,
            selection: TextSelection.collapsed(offset: c.query.length),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: cs.surfaceContainerHigh,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      showReplace ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => showReplace = !showReplace),
                    tooltip: 'Toggle replace',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _queryField,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Find',
                        border: const OutlineInputBorder(),
                        suffixText: c.matchCount > 0
                            ? '${(c.currentIndex < 0 ? 0 : c.currentIndex + 1)}/${c.matchCount}'
                            : null,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) {
                        c.query = v;
                        c.search(jumpToFirst: true);
                      },
                    ),
                  ),
                  _OptionChip(
                    label: 'Aa',
                    selected: c.caseSensitive,
                    tooltip: 'Match case',
                    onTap: () {
                      c.caseSensitive = !c.caseSensitive;
                      c.search(jumpToFirst: true);
                    },
                  ),
                  _OptionChip(
                    label: '.*',
                    selected: c.useRegex,
                    tooltip: 'Regex',
                    onTap: () {
                      c.useRegex = !c.useRegex;
                      c.search(jumpToFirst: true);
                    },
                  ),
                  _OptionChip(
                    label: 'W',
                    selected: c.wholeWord,
                    tooltip: 'Whole word',
                    onTap: () {
                      c.wholeWord = !c.wholeWord;
                      c.search(jumpToFirst: true);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                    tooltip: 'Previous match',
                    onPressed: c.previous,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                    tooltip: 'Next match',
                    onPressed: c.next,
                  ),
                ],
              ),
              if (showReplace)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 40),
                      Expanded(
                        child: TextField(
                          controller: _replaceField,
                          onChanged: (v) => c.replacement = v,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Replace',
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.find_replace, size: 18),
                        onPressed: c.replaceCurrent,
                        tooltip: 'Replace',
                      ),
                      TextButton(
                        onPressed: c.replaceAll,
                        child: const Text('All'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: selected,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white24,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
