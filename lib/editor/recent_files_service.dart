import 'package:shared_preferences/shared_preferences.dart';

class RecentFilesService {
  static const _key = 'recent_files';
  static const _max = 15;

  static RecentFilesService? _instance;
  static RecentFilesService get instance => _instance ??= RecentFilesService._();
  RecentFilesService._();

  List<String> _files = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _files = prefs.getStringList(_key) ?? [];
    _loaded = true;
  }

  Future<List<String>> getAll() async {
    await _ensureLoaded();
    return List.unmodifiable(_files);
  }

  Future<void> add(String path) async {
    await _ensureLoaded();
    _files.remove(path);
    _files.insert(0, path);
    if (_files.length > _max) _files = _files.sublist(0, _max);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _files);
  }

  Future<void> remove(String path) async {
    await _ensureLoaded();
    _files.remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _files);
  }

  Future<void> clear() async {
    _files = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
