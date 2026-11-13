import 'package:flutter/painting.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart' as monokai_sublime;
import 'package:flutter_highlight/themes/monokai.dart' as monokai;
import 'package:flutter_highlight/themes/vs2015.dart' as vs2015;
import 'package:flutter_highlight/themes/dracula.dart' as dracula;
import 'package:flutter_highlight/themes/github.dart' as github;
import 'package:flutter_highlight/themes/androidstudio.dart' as android_studio;

import 'bcode_theme.dart';

class SyntaxTheme {
  final String id;
  final String name;
  final Map<String, TextStyle> styles;

  const SyntaxTheme({
    required this.id,
    required this.name,
    required this.styles,
  });
}

class SyntaxThemes {
  SyntaxThemes._();

  static final monokaiSublime = SyntaxTheme(
    id: 'monokai_sublime',
    name: 'Monokai Sublime',
    styles: completeHighlightStyles({
      ...monokai_sublime.monokaiSublimeTheme,
      'string': const TextStyle(color: Color(0xffff6b6b)),
      'built_in': const TextStyle(color: Color(0xffa6e22e)),
      'builtin-name': const TextStyle(color: Color(0xffa6e22e)),
      'function': const TextStyle(color: Color(0xffa6e22e)),
    }),
  );

  static final draculaTheme = SyntaxTheme(
    id: 'dracula',
    name: 'Dracula',
    styles: completeHighlightStyles({
      ...dracula.draculaTheme,
      'string': const TextStyle(color: Color(0xfff1fa8c)),
      'built_in': const TextStyle(color: Color(0xff8be9fd)),
      'function': const TextStyle(color: Color(0xff50fa7b)),
    }),
  );

  static final githubDark = SyntaxTheme(
    id: 'github_dark',
    name: 'GitHub Dark',
    styles: completeHighlightStyles({
      ...github.githubTheme,
      'keyword': const TextStyle(color: Color(0xffff7b72)),
      'string': const TextStyle(color: Color(0xffa5d6ff)),
      'comment': const TextStyle(color: Color(0xff8b949e)),
      'function': const TextStyle(color: Color(0xffd2a8ff)),
      'number': const TextStyle(color: Color(0xff79c0ff)),
      'built_in': const TextStyle(color: Color(0xffffa657)),
      'type': const TextStyle(color: Color(0xffffa657)),
    }),
  );

  static final androidStudioTheme = SyntaxTheme(
    id: 'android_studio',
    name: 'Android Studio',
    styles: completeHighlightStyles(android_studio.androidstudioTheme),
  );

  static final vs2015Theme = SyntaxTheme(
    id: 'vs2015',
    name: 'VS 2015',
    styles: completeHighlightStyles(vs2015.vs2015Theme),
  );

  static final monokaiTheme = SyntaxTheme(
    id: 'monokai',
    name: 'Monokai',
    styles: completeHighlightStyles(monokai.monokaiTheme),
  );

  static final all = [
    monokaiSublime,
    draculaTheme,
    githubDark,
    androidStudioTheme,
    vs2015Theme,
    monokaiTheme,
  ];

  static void register(SyntaxTheme theme) {
    if (all.any((existing) => existing.id == theme.id)) return;
    all.add(theme);
  }

  static void unregisterExtension(String extensionId) {
    final prefix = 'ext.$extensionId.';
    all.removeWhere((theme) => theme.id.startsWith(prefix));
  }

  static SyntaxTheme fromId(String id) {
    return all.firstWhere(
      (t) => t.id == id,
      orElse: () => monokaiSublime,
    );
  }
}
