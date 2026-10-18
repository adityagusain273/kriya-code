import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which extensions the user has "installed" from the Extensions tab.
class ExtensionInstallStore extends ChangeNotifier {
  static const _key = 'extensions_installed';
  final SharedPreferences prefs;

  ExtensionInstallStore(this.prefs);

  List<String> get _installed => prefs.getStringList(_key) ?? const [];

  bool isInstalled(String extensionId) => _installed.contains(extensionId);

  void install(String extensionId) {
    final list = _installed.toList();
    if (!list.contains(extensionId)) list.add(extensionId);
    prefs.setStringList(_key, list);
    notifyListeners();
  }

  void uninstall(String extensionId) {
    final list = _installed.toList()..remove(extensionId);
    prefs.setStringList(_key, list);
    notifyListeners();
  }
}
