import 'package:flutter/painting.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

final bcodeTheme = <String, TextStyle>{
  ...monokaiSublimeTheme,
  'string': const TextStyle(color: Color(0xffff6b6b)),
  'built_in': const TextStyle(color: Color(0xffa6e22e)),
  'builtin-name': const TextStyle(color: Color(0xffa6e22e)),
  'function': const TextStyle(color: Color(0xffa6e22e)),
  // Bracket pair colorization
  'bracket-1': const TextStyle(color: Color(0xFFFFEAA7)), // Yellow
  'bracket-2': const TextStyle(color: Color(0xFFDDA0DD)), // Plum
  'bracket-3': const TextStyle(color: Color(0xFF45B7D1)), // Blue
  'bracket-4': const TextStyle(color: Color(0xFFFF6B6B)), // Red
  'bracket-5': const TextStyle(color: Color(0xFF4ECDC4)), // Teal
  'bracket-6': const TextStyle(color: Color(0xFF96CEB4)), // Green
  'bracket-7': const TextStyle(color: Color(0xFF98D8C8)), // Mint
  'bracket-8': const TextStyle(color: Color(0xFFF7DC6F)), // Gold
};
