import 'dart:async';

import 'package:flutter/foundation.dart';

import 'autocomplete_item.dart';
import 'keyword_provider.dart';
import 'symbol_indexer.dart';

class AutocompleteEngine extends ChangeNotifier {
  String? _languageId;
  String _prefix = '';
  List<AutocompleteItem> _suggestions = [];
  Timer? _debounce;

  String? get languageId => _languageId;
  List<AutocompleteItem> get suggestions => _suggestions;

  void setLanguage(String? id) {
    if (_languageId == id) return;
    _languageId = id;
    _suggestions = [];
    notifyListeners();
  }

  void onTextChanged(String text, int cursorOffset) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _compute(text, cursorOffset);
    });
  }

  void _compute(String text, int cursorOffset) {
    final prefix = _extractPrefix(text, cursorOffset);
    if (prefix == _prefix && _suggestions.isNotEmpty) return;
    _prefix = prefix;

    if (prefix.isEmpty) {
      if (_suggestions.isNotEmpty) {
        _suggestions = [];
        notifyListeners();
      }
      return;
    }

    final symbolItems = SymbolIndexer.index(text, _languageId);
    final keywordItems = KeywordProvider.forLanguage(_languageId);
    final all = <AutocompleteItem>{...symbolItems, ...keywordItems};

    final lp = prefix.toLowerCase();
    final filtered = all
        .where((item) => item.label.toLowerCase().startsWith(lp) && item.label != prefix)
        .toList();

    filtered.sort((a, b) {
      final aExact = a.label.toLowerCase() == lp ? 0 : 1;
      final bExact = b.label.toLowerCase() == lp ? 0 : 1;
      if (aExact != bExact) return aExact - bExact;
      final kindOrder = _kindOrder(a.kind) - _kindOrder(b.kind);
      if (kindOrder != 0) return kindOrder;
      return a.label.compareTo(b.label);
    });

    _suggestions = filtered.take(20).toList();
    notifyListeners();
  }

  int _kindOrder(int kind) {
    switch (kind) {
      case AutocompleteKind.function_:
        return 0;
      case AutocompleteKind.class_:
        return 1;
      case AutocompleteKind.variable:
        return 2;
      case AutocompleteKind.keyword:
        return 3;
      case AutocompleteKind.snippet:
        return 4;
      default:
        return 5;
    }
  }

  String _extractPrefix(String text, int cursorOffset) {
    if (cursorOffset <= 0 || cursorOffset > text.length) return '';
    int start = cursorOffset - 1;
    while (start >= 0 && _isWordChar(text[start])) {
      start--;
    }
    return text.substring(start + 1, cursorOffset);
  }

  bool _isWordChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) ||
        c == 95;
  }

  void dismiss() {
    _prefix = '';
    if (_suggestions.isNotEmpty) {
      _suggestions = [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
