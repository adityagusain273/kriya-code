import 'package:highlight/highlight_core.dart';

import 'language_pack.dart';

class HighlightEngine {
  final _packs = <String, LanguagePack>{};
  final _extMap = <String, LanguagePack>{};
  final _deferredLoaders = <String, Future<LanguagePack> Function()>{};

  void register(LanguagePack pack) {
    _packs[pack.id] = pack;
    for (final ext in pack.fileExtensions) {
      _extMap[ext.toLowerCase()] = pack;
    }
  }

  bool hasLanguage(String id) => _packs.containsKey(id);

  bool hasExtension(String extension) =>
      _extMap.containsKey(extension.toLowerCase());

  void unregister(String id) {
    final pack = _packs.remove(id);
    if (pack == null) return;
    _extMap.removeWhere((_, value) => identical(value, pack));
  }

  void registerDeferred(String languageId, Future<LanguagePack> Function() loader) {
    _deferredLoaders[languageId] = loader;
  }

  Future<LanguagePack?> _loadIfNeeded(String? languageId) async {
    if (languageId == null) return null;
    if (_packs.containsKey(languageId)) return _packs[languageId];
    final loader = _deferredLoaders[languageId];
    if (loader == null) return null;
    _deferredLoaders.remove(languageId);
    final pack = await loader();
    register(pack);
    return pack;
  }

  Future<LanguagePack?> forId(String? id) async => _loadIfNeeded(id);

  Future<LanguagePack?> forFile(String fileName) async {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = fileName.substring(dot + 1).toLowerCase();
    if (_extMap.containsKey(ext)) return _extMap[ext]!;

    for (final entry in _deferredLoaders.entries.toList()) {
      final pack = await entry.value();
      _deferredLoaders.remove(entry.key);
      if (pack.fileExtensions.contains(ext)) {
        register(pack);
        return pack;
      }
    }
    return null;
  }

  Future<Mode?> grammarFor(String? languageId) async =>
      languageId == null ? null : (await _loadIfNeeded(languageId))?.grammar;

  Future<IndentRules> indentRulesFor(String? languageId) async =>
      (await _loadIfNeeded(languageId))?.indentRules ?? const IndentRules();

  List<LanguagePack> get all => List.unmodifiable(_packs.values);
}
