import 'package:flutter/painting.dart';
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/all.dart';

import '../../editor/highlighting/bcode_theme.dart';
import '../../editor/highlighting/highlight_engine.dart';
import '../../editor/highlighting/language_pack.dart';
import '../../editor/highlighting/syntax_themes.dart';
import '../../editor/snippets.dart';
import 'extension_installer.dart';
import 'extension_manifest.dart';

class ExtensionLanguagePack implements LanguagePack {
  final ExtensionLanguage language;

  const ExtensionLanguagePack(this.language);

  @override
  String get id => language.id;

  @override
  String get displayName => language.name;

  @override
  List<String> get fileExtensions => language.extensions;

  @override
  Mode get grammar => allLanguages[language.grammar]!;

  @override
  IndentRules get indentRules => IndentRules(
        indentWidth: language.indentWidth,
        insertSpaces: language.insertSpaces,
        blockOpeners: language.blockOpeners,
        blockClosers: language.blockClosers,
      );
}

class ExtensionRegistration {
  final String extensionId;
  final List<String> languageIds;
  final List<String> snippetLanguages;
  final List<String> themeIds;

  const ExtensionRegistration({
    required this.extensionId,
    required this.languageIds,
    required this.snippetLanguages,
    required this.themeIds,
  });
}

/// Registers an installed package's contributions with the live registries.
///
/// Bundled languages always win: a package that claims `py` or `python` was
/// already refused at install time, and this repeats the check at load time in
/// case the manifest was edited on disk afterwards.
class ExtensionLoader {
  final HighlightEngine engine;
  final Map<String, ExtensionRegistration> _registrations = {};

  ExtensionLoader({required this.engine});

  Iterable<String> get activeIds => _registrations.keys;

  void activate(Iterable<InstalledExtension> extensions) {
    for (final extension in extensions) {
      activateOne(extension);
    }
  }

  ExtensionRegistration activateOne(InstalledExtension extension) {
    deactivate(extension.manifest.id);

    final languageIds = <String>[];
    for (final language in extension.manifest.languages) {
      final clashes = engine.hasLanguage(language.id) ||
          language.extensions.any(engine.hasExtension);
      if (clashes) {
        // A shortcut, not a bug: re-registering would let a package replace a
        // bundled grammar. The user can remove the conflicting extension.
        continue;
      }
      engine.register(ExtensionLanguagePack(language));
      languageIds.add(language.id);
    }

    final snippetLanguages = <String>[];
    for (final entry in extension.manifest.snippets.entries) {
      SnippetService.registerExternal(
        extension.manifest.id,
        entry.key,
        entry.value
            .map((snippet) => Snippet(
                  prefix: snippet.prefix,
                  label: snippet.label,
                  body: snippet.body,
                  description: snippet.description,
                  scope: [entry.key],
                ))
            .toList(),
      );
      snippetLanguages.add(entry.key);
    }

    final themeIds = <String>[];
    for (final theme in extension.manifest.themes) {
      final id = 'ext.${extension.manifest.id}.${theme.id}';
      SyntaxThemes.register(
        SyntaxTheme(
          id: id,
          name: theme.name,
          styles: completeHighlightStyles({
            for (final entry in theme.colors.entries)
              entry.key: TextStyle(color: _color(entry.value)),
            'root': TextStyle(
              color: _color(theme.colors['foreground']!),
              backgroundColor: _color(theme.colors['background']!),
            ),
          }),
        ),
      );
      themeIds.add(id);
    }

    final registration = ExtensionRegistration(
      extensionId: extension.manifest.id,
      languageIds: List.unmodifiable(languageIds),
      snippetLanguages: List.unmodifiable(snippetLanguages),
      themeIds: List.unmodifiable(themeIds),
    );
    _registrations[extension.manifest.id] = registration;
    return registration;
  }

  ExtensionRegistration? deactivate(String extensionId) {
    final registration = _registrations.remove(extensionId);
    if (registration == null) return null;

    for (final languageId in registration.languageIds) {
      engine.unregister(languageId);
    }
    SnippetService.unregisterExternal(extensionId);
    SyntaxThemes.unregisterExtension(extensionId);
    return registration;
  }
}

void activateExtensions(
  Iterable<InstalledExtension> extensions, {
  required HighlightEngine engine,
}) {
  ExtensionLoader(engine: engine).activate(extensions);
}

Color _color(String hex) {
  var value = hex.substring(1);
  if (value.length == 3) {
    value = value.split('').map((char) => '$char$char').join();
  }
  if (value.length == 6) value = 'ff$value';
  return Color(int.parse(value, radix: 16));
}
