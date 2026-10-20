import 'package:flutter/painting.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

/// Bracket pair palette, keyed by nesting depth.
///
/// `BCodeController._colorizeBrackets` rewrites the class of every bracket it walks
/// to `bracket-1` … `bracket-8`. An undefined `bracket-N` is worse than a merely
/// missing colour: the bracket stops inheriting the colour of the token it belongs
/// to and falls back to plain body text. The Python grammar, for example, hands the
/// highlighter `print(` as a single `built_in` token, so the `(` used to be green and
/// turned body-coloured the moment bracket colourisation was switched on.
///
/// Defined once, here, because the palette previously existed only in [bcodeTheme]
/// — a map that nothing but a default field ever read — while the editor renders
/// with `SyntaxThemes`. Bracket colourisation was therefore dead in the app even
/// though the colours were right there in the source.
const bracketPalette = <String, Color>{
  'bracket-1': Color(0xFFFFEAA7),
  'bracket-2': Color(0xFFDDA0DD),
  'bracket-3': Color(0xFF45B7D1),
  'bracket-4': Color(0xFFFF6B6B),
  'bracket-5': Color(0xFF4ECDC4),
  'bracket-6': Color(0xFF96CEB4),
  'bracket-7': Color(0xFF98D8C8),
  'bracket-8': Color(0xFFF7DC6F),
};

/// Token classes the bundled grammars emit that the upstream themes omit, and the
/// keys each should take its colour from instead.
///
/// Measured across the ten bundled packs: `class` is absent from five of the six
/// upstream themes, so class names rendered as body text in Java, C++, JavaScript
/// and TypeScript. `meta`, `meta-keyword` and `meta-string` are absent from all of
/// them, leaving `#include <stdio.h>` and `<!DOCTYPE html>` uncoloured. Before this
/// table the only measurable colourable coverage was 35% for Java and 43% for C++.
///
/// The first donor key the theme actually defines wins, so a theme that does style
/// the token keeps its own colour and only the genuinely missing ones are filled in.
const tokenFallbacks = <String, List<String>>{
  'class': ['type', 'title', 'keyword'],
  'meta-keyword': ['keyword'],
  'meta-string': ['string'],
  'meta': ['keyword'],
  'attr': ['string'],
  'attribute': ['attr', 'string'],
  'code': ['string'],
  'number': ['literal'],
  'literal': ['built_in', 'number'],
  'built_in': ['literal', 'number'],
  'params': ['variable', 'string'],
  'selector-class': ['attr', 'string'],
  'tag': ['name', 'keyword'],
  'name': ['tag', 'keyword'],
  'section': ['keyword'],
  'bullet': ['string'],
  'title': ['function', 'class'],
  'function': ['title', 'class'],
};

/// Returns [styles] with every token class a bundled grammar can emit.
///
/// `CodeThemeData` uses the map it is given *instead of* the package defaults, and
/// the span builder resolves an unknown class to the inherited style. A token class
/// missing from the map is therefore not cosmetic: it silently renders as
/// uncoloured body text. Running every theme through this keeps that from depending
/// on what a given upstream theme happens to ship.
Map<String, TextStyle> completeHighlightStyles(Map<String, TextStyle> styles) {
  final out = Map<String, TextStyle>.of(styles);

  for (final entry in bracketPalette.entries) {
    out.putIfAbsent(entry.key, () => TextStyle(color: entry.value));
  }

  for (final entry in tokenFallbacks.entries) {
    if (out.containsKey(entry.key)) continue;
    for (final donor in entry.value) {
      final style = out[donor];
      if (style != null) {
        out[entry.key] = style;
        break;
      }
    }
  }

  return out;
}

/// Fallback palette for callers that do not pick a theme themselves.
final bcodeTheme = <String, TextStyle>{
  ...completeHighlightStyles(monokaiSublimeTheme),
  'string': const TextStyle(color: Color(0xffff6b6b)),
  'built_in': const TextStyle(color: Color(0xffa6e22e)),
  'builtin-name': const TextStyle(color: Color(0xffa6e22e)),
  'function': const TextStyle(color: Color(0xffa6e22e)),
};
