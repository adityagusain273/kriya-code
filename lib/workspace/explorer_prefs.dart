import 'package:shared_preferences/shared_preferences.dart';

class ExplorerPrefs {
  static const _key = 'explorer_expanded_dirs';
  static const _hiddenKey = 'explorer_show_hidden';
  final SharedPreferences prefs;

  ExplorerPrefs(this.prefs);

  Set<String> loadExpanded() =>
      (prefs.getStringList(_key) ?? const <String>[]).toSet();

  void saveExpanded(Set<String> paths) {
    final sorted = paths.toList()..sort();
    prefs.setStringList(_key, sorted);
  }

  bool loadShowHidden() => prefs.getBool(_hiddenKey) ?? false;

  void saveShowHidden(bool value) => prefs.setBool(_hiddenKey, value);
}
