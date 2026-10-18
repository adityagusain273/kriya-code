import 'package:shared_preferences/shared_preferences.dart';

class ExplorerPrefs {
  static const _key = 'explorer_expanded_dirs';
  final SharedPreferences prefs;

  ExplorerPrefs(this.prefs);

  Set<String> loadExpanded() =>
      (prefs.getStringList(_key) ?? const <String>[]).toSet();

  void saveExpanded(Set<String> paths) {
    final sorted = paths.toList()..sort();
    prefs.setStringList(_key, sorted);
  }
}
