import 'dart:convert';

import 'package:highlight/languages/all.dart';

/// Thrown when an extension package is malformed or asks for something the
/// app cannot support. The message is shown to the person installing it.
class ExtensionFormatException implements Exception {
  final String message;

  const ExtensionFormatException(this.message);

  @override
  String toString() => message;
}

class ExtensionManifest {
  static const supportedManifestVersion = 1;

  final int manifestVersion;
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String license;
  final String homepage;
  final List<ExtensionLanguage> languages;
  final Map<String, List<ExtensionSnippet>> snippets;
  final List<ExtensionTheme> themes;

  const ExtensionManifest({
    required this.manifestVersion,
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.author = '',
    this.license = '',
    this.homepage = '',
    this.languages = const [],
    this.snippets = const {},
    this.themes = const [],
  });

  bool get hasContributions =>
      languages.isNotEmpty || snippets.isNotEmpty || themes.isNotEmpty;

  factory ExtensionManifest.parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ExtensionFormatException(
          'extension.json is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const ExtensionFormatException(
          'extension.json must contain an object.');
    }
    final json = Map<String, dynamic>.from(decoded);

    final manifestVersion = _int(json['manifestVersion'], 'manifestVersion');
    if (manifestVersion != supportedManifestVersion) {
      throw ExtensionFormatException(
        'Unsupported manifestVersion $manifestVersion. '
        'This version of B Code reads version $supportedManifestVersion.',
      );
    }

    final id = _string(json['id'], 'id');
    _checkId(id, 'extension id');
    if (id.startsWith('bcode.')) {
      throw const ExtensionFormatException(
        'Extension ids starting with "bcode." are reserved for bundled extensions.',
      );
    }

    final name = _string(json['name'], 'name');
    final version = _string(json['version'] ?? '1.0.0', 'version');
    if (!_versionPattern.hasMatch(version)) {
      throw const ExtensionFormatException(
        'version must be 1-32 letters, digits, dots, dashes, plus signs or '
        'underscores.',
      );
    }

    final contributes = json['contributes'];
    if (contributes != null && contributes is! Map) {
      throw const ExtensionFormatException('contributes must be an object.');
    }
    final contributesMap = contributes is Map
        ? Map<String, dynamic>.from(contributes)
        : const <String, dynamic>{};

    final languages = <ExtensionLanguage>[];
    final languageIds = <String>{};
    final extensions = <String>{};
    final rawLanguages = contributesMap['languages'];
    if (rawLanguages != null) {
      if (rawLanguages is! List) {
        throw const ExtensionFormatException(
            'contributes.languages must be a list.');
      }
      if (rawLanguages.length > 20) {
        throw const ExtensionFormatException(
          'An extension can contribute at most 20 languages.',
        );
      }
      for (final entry in rawLanguages) {
        if (entry is! Map) {
          throw const ExtensionFormatException(
            'Each contributes.languages entry must be an object.',
          );
        }
        final language = ExtensionLanguage.parse(
          Map<String, dynamic>.from(entry),
          languageIds,
          extensions,
        );
        languages.add(language);
      }
    }

    final snippets = <String, List<ExtensionSnippet>>{};
    var snippetCount = 0;
    final rawSnippets = contributesMap['snippets'];
    if (rawSnippets != null) {
      if (rawSnippets is! Map) {
        throw const ExtensionFormatException(
            'contributes.snippets must be an object.');
      }
      for (final languageEntry in rawSnippets.entries) {
        final languageId = languageEntry.key.toString();
        _checkLanguageId(languageId, 'contribututes.snippets key');
        final value = languageEntry.value;
        if (value is! Map) {
          throw ExtensionFormatException(
            'Snippets for "$languageId" must be an object keyed by trigger.',
          );
        }
        final list = <ExtensionSnippet>[];
        for (final snippetEntry in value.entries) {
          snippetCount++;
          if (snippetCount > 500) {
            throw const ExtensionFormatException(
              'An extension can contribute at most 500 snippets.',
            );
          }
          final prefix = snippetEntry.key.toString();
          final snippet = snippetEntry.value;
          if (snippet is! Map) {
            throw ExtensionFormatException(
              'Snippet "$prefix" in "$languageId" must be an object.',
            );
          }
          list.add(ExtensionSnippet.parse(
            prefix,
            Map<String, dynamic>.from(snippet),
          ));
        }
        snippets[languageId] = List.unmodifiable(list);
      }
    }

    final themes = <ExtensionTheme>[];
    final rawThemes = contributesMap['themes'];
    if (rawThemes != null) {
      if (rawThemes is! List) {
        throw const ExtensionFormatException(
            'contributes.themes must be a list.');
      }
      if (rawThemes.length > 10) {
        throw const ExtensionFormatException(
          'An extension can contribute at most 10 themes.',
        );
      }
      final themeIds = <String>{};
      for (final entry in rawThemes) {
        if (entry is! Map) {
          throw const ExtensionFormatException(
            'Each contributes.themes entry must be an object.',
          );
        }
        final theme = ExtensionTheme.parse(Map<String, dynamic>.from(entry));
        if (!themeIds.add(theme.id)) {
          throw ExtensionFormatException('Duplicate theme id: ${theme.id}');
        }
        themes.add(theme);
      }
    }

    return ExtensionManifest(
      manifestVersion: manifestVersion,
      id: id,
      name: name,
      version: version,
      description: _optionalString(json['description'], 'description'),
      author: _optionalString(json['author'], 'author'),
      license: _optionalString(json['license'], 'license'),
      homepage: _optionalString(json['homepage'], 'homepage'),
      languages: List.unmodifiable(languages),
      snippets: Map.unmodifiable(snippets),
      themes: List.unmodifiable(themes),
    );
  }
}

class ExtensionLanguage {
  final String id;
  final String name;
  final List<String> extensions;
  final String grammar;
  final int indentWidth;
  final bool insertSpaces;
  final List<String> blockOpeners;
  final List<String> blockClosers;

  const ExtensionLanguage({
    required this.id,
    required this.name,
    required this.extensions,
    required this.grammar,
    this.indentWidth = 4,
    this.insertSpaces = true,
    this.blockOpeners = const [],
    this.blockClosers = const [],
  });

  factory ExtensionLanguage.parse(
    Map<String, dynamic> json,
    Set<String> usedIds,
    Set<String> usedExtensions,
  ) {
    final id = _string(json['id'], 'language id');
    _checkLanguageId(id, 'language id');
    if (_builtinLanguageIds.contains(id)) {
      throw ExtensionFormatException(
        'Language "$id" is built into B Code and cannot be replaced.',
      );
    }
    if (!usedIds.add(id)) {
      throw ExtensionFormatException('Duplicate language id: $id');
    }

    final name = _string(json['name'], 'language name');
    final grammar = _string(json['grammar'], 'grammar for "$id"');
    if (!allLanguages.containsKey(grammar)) {
      throw ExtensionFormatException(
        'Unknown grammar "$grammar" for "$id". Use a highlight.js grammar '
        'name such as rust, go, kotlin, swift, ruby, php, sql or yaml.',
      );
    }

    final rawExtensions = json['extensions'];
    if (rawExtensions is! List || rawExtensions.isEmpty) {
      throw ExtensionFormatException(
        'Language "$id" must list at least one file extension.',
      );
    }
    if (rawExtensions.length > 20) {
      throw ExtensionFormatException(
        'Language "$id" lists more than 20 file extensions.',
      );
    }
    final extensions = <String>[];
    for (final entry in rawExtensions) {
      final extension = entry.toString().toLowerCase().trim();
      if (!_extensionPattern.hasMatch(extension)) {
        throw ExtensionFormatException(
          'Invalid file extension "$extension" for "$id". '
          'Use letters, digits, +, - or _ without a dot.',
        );
      }
      if (_builtinExtensions.contains(extension)) {
        throw ExtensionFormatException(
          '".$extension" is already claimed by a bundled language.',
        );
      }
      if (!usedExtensions.add(extension)) {
        throw ExtensionFormatException('Duplicate file extension: .$extension');
      }
      extensions.add(extension);
    }

    final indentWidth = json['indentWidth'] == null
        ? 4
        : _int(json['indentWidth'], 'indentWidth for "$id"');
    if (indentWidth < 1 || indentWidth > 8) {
      throw ExtensionFormatException(
        'indentWidth for "$id" must be between 1 and 8.',
      );
    }

    return ExtensionLanguage(
      id: id,
      name: name,
      extensions: List.unmodifiable(extensions),
      grammar: grammar,
      indentWidth: indentWidth,
      insertSpaces: json['insertSpaces'] != false,
      blockOpeners: _stringList(json['blockOpeners'], 'blockOpeners for "$id"'),
      blockClosers: _stringList(json['blockClosers'], 'blockClosers for "$id"'),
    );
  }
}

class ExtensionSnippet {
  final String prefix;
  final String label;
  final String body;
  final String description;

  const ExtensionSnippet({
    required this.prefix,
    required this.label,
    required this.body,
    this.description = '',
  });

  factory ExtensionSnippet.parse(String prefix, Map<String, dynamic> json) {
    if (prefix.isEmpty || prefix.length > 40) {
      throw const ExtensionFormatException(
        'Snippet triggers must be 1 to 40 characters.',
      );
    }
    final rawBody = json['body'];
    String body;
    if (rawBody is String) {
      body = rawBody;
    } else if (rawBody is List) {
      body = rawBody.map((line) {
        if (line is! String) {
          throw const ExtensionFormatException(
            'Snippet body lines must be strings.',
          );
        }
        return line;
      }).join('\n');
    } else {
      throw const ExtensionFormatException(
        'Snippet body must be a string or a list of lines.',
      );
    }
    if (body.length > 4000) {
      throw const ExtensionFormatException(
        'Snippet bodies are limited to 4000 characters.',
      );
    }
    final label = _optionalString(json['label'], 'snippet label');
    if (label.length > 80) {
      throw const ExtensionFormatException(
        'Snippet labels are limited to 80 characters.',
      );
    }
    return ExtensionSnippet(
      prefix: prefix,
      label: label.isEmpty ? prefix : label,
      body: body,
      description: _optionalString(json['description'], 'snippet description'),
    );
  }
}

class ExtensionTheme {
  final String id;
  final String name;
  final Map<String, String> colors;

  const ExtensionTheme({
    required this.id,
    required this.name,
    required this.colors,
  });

  factory ExtensionTheme.parse(Map<String, dynamic> json) {
    final id = _string(json['id'], 'theme id');
    if (!_themeIdPattern.hasMatch(id)) {
      throw ExtensionFormatException(
        'Invalid theme id "$id". Use lowercase letters, digits, dots, dashes '
        'or underscores.',
      );
    }
    final name = _string(json['name'], 'theme name');
    final rawColors = json['colors'];
    if (rawColors is! Map) {
      throw ExtensionFormatException(
          'Theme "$id" must provide a colors object.');
    }
    final colors = <String, String>{};
    for (final entry in rawColors.entries) {
      final key = entry.key.toString();
      final value = entry.value.toString();
      if (!_colorPattern.hasMatch(value)) {
        throw ExtensionFormatException(
          'Theme "$id" has an invalid colour for "$key": $value. '
          'Use #RGB, #RRGGBB or #AARRGGBB.',
        );
      }
      colors[key] = value;
    }
    if (!colors.containsKey('background') ||
        !colors.containsKey('foreground')) {
      throw ExtensionFormatException(
        'Theme "$id" must define background and foreground colours.',
      );
    }
    if (colors.length > 200) {
      throw ExtensionFormatException(
          'Theme "$id" defines more than 200 colours.');
    }
    return ExtensionTheme(
      id: id,
      name: name,
      colors: Map.unmodifiable(colors),
    );
  }
}

const _builtinLanguageIds = <String>{
  // Keep in sync with lib/editor/highlighting/packs/ and the built-in list in
  // lib/plugins/builtin/builtin_extensions.dart.
  'python',
  'java',
  'c',
  'cpp',
  'javascript',
  'typescript',
  'html',
  'css',
  'json',
  'markdown',
};

const _builtinExtensions = <String>{
  'py',
  'pyw',
  'java',
  'c',
  'h',
  'cpp',
  'cc',
  'cxx',
  'hpp',
  'hh',
  'js',
  'mjs',
  'cjs',
  'ts',
  'tsx',
  'html',
  'htm',
  'css',
  'json',
  'md',
  'mkdown',
  'mkd',
};

final _idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,79}$');
final _versionPattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z._+-]{0,31}$');
final _languageIdPattern = RegExp(r'^[a-z][a-z0-9_+-]{0,39}$');
final _themeIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');
final _extensionPattern = RegExp(r'^[a-z0-9][a-z0-9_+-]{0,9}$');
final _colorPattern =
    RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

void _checkId(String value, String label) {
  if (!_idPattern.hasMatch(value)) {
    throw ExtensionFormatException(
      'Invalid $label "$value". Use 3-80 lowercase letters, digits, dots, '
      'dashes or underscores.',
    );
  }
}

void _checkLanguageId(String value, String label) {
  if (!_languageIdPattern.hasMatch(value)) {
    throw ExtensionFormatException(
      'Invalid $label "$value". Use lowercase letters, digits, _, + or -.',
    );
  }
}

String _string(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw ExtensionFormatException('$field is required and must be text.');
  }
  final trimmed = value.trim();
  if (trimmed.length > 120) {
    throw ExtensionFormatException('$field must be 120 characters or fewer.');
  }
  return trimmed;
}

String _optionalString(Object? value, String field) {
  if (value == null) return '';
  if (value is! String) {
    throw ExtensionFormatException('$field must be text.');
  }
  if (value.length > 2000) {
    throw ExtensionFormatException('$field is too long.');
  }
  return value.trim();
}

int _int(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw ExtensionFormatException('$field must be a whole number.');
}

List<String> _stringList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    throw ExtensionFormatException('$field must be a list of strings.');
  }
  return List.unmodifiable(value.map((entry) {
    if (entry is! String) {
      throw ExtensionFormatException('$field must be a list of strings.');
    }
    return entry;
  }));
}
