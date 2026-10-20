import 'package:flutter/material.dart' show TextStyle;
import 'package:highlight/highlight.dart';

import '../../plugins/host/language_registry.dart';
import 'bcode_theme.dart';
import 'highlight_engine.dart';

class HighlightService {
  final LanguageRegistry registry;
  final HighlightEngine engine;
  final Map<String, TextStyle> theme;

  HighlightService({
    required this.registry,
    required this.engine,
    Map<String, TextStyle>? theme,
  }) : theme = theme ?? bcodeTheme;

  Future<String?> languageIdFor(String filePath) async {
    final name = filePath.split('/').last;
    final fromEngine = await engine.forFile(name);
    if (fromEngine != null) return fromEngine.id;
    return registry.byFileName(name)?.id;
  }

  Future<Mode?> grammarFor(String? languageId) async =>
      languageId == null ? null : engine.grammarFor(languageId);

  Future<int> indentWidthFor(String? languageId) async =>
      (await engine.indentRulesFor(languageId)).indentWidth;
}