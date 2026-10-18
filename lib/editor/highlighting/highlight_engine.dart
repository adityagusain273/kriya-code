import 'package:highlight/highlight_core.dart';

import '../../plugins/api/run_config.dart';
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

  void registerDeferred(String languageId, Future<LanguagePack> Function() loader) {
    _deferredLoaders[languageId] = loader;
  }

  Future<LanguagePack?> _loadIfNeeded(String? languageId) async {
    if (languageId == null) return null;
    if (_packs.containsKey(languageId)) return _packs[languageId];
    final loader = _deferredLoaders[languageId];
    if (loader == null) return null;
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

    for (final entry in _deferredLoaders.entries) {
      final pack = await entry.value();
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

  Future<RunConfig?> runConfigFor(String? languageId) async =>
      (await _loadIfNeeded(languageId))?.runConfig;

  List<LanguagePack> get all => List.unmodifiable(_packs.values);
}