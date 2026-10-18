import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  final SharedPreferences prefs;

  SettingsStore(this.prefs);

  double get fontSize => prefs.getDouble('editor_font_size') ?? 14;
  set fontSize(double v) {
    prefs.setDouble('editor_font_size', v);
    notifyListeners();
  }

  int get tabSize => prefs.getInt('editor_tab_size') ?? 4;
  set tabSize(int v) {
    prefs.setInt('editor_tab_size', v);
    notifyListeners();
  }

  ThemeMode get themeMode =>
      ThemeMode.values[(prefs.getInt('theme_mode') ?? 2).clamp(0, ThemeMode.values.length - 1)];
  set themeMode(ThemeMode mode) {
    prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }

  bool get autoSave => prefs.getBool('auto_save') ?? true;
  set autoSave(bool v) {
    prefs.setBool('auto_save', v);
    notifyListeners();
  }

  bool get onboardingComplete => prefs.getBool('onboarding_complete') ?? false;
  set onboardingComplete(bool v) {
    prefs.setBool('onboarding_complete', v);
    notifyListeners();
  }

  int get autoSaveDelayMs => prefs.getInt('auto_save_delay') ?? 1500;
  set autoSaveDelayMs(int v) {
    prefs.setInt('auto_save_delay', v);
    notifyListeners();
  }

  String get syntaxThemeId => prefs.getString('syntax_theme') ?? 'monokai_sublime';
  set syntaxThemeId(String v) {
    prefs.setString('syntax_theme', v);
    notifyListeners();
  }

  String get gitName => prefs.getString('git_name') ?? '';
  set gitName(String v) {
    prefs.setString('git_name', v);
    notifyListeners();
  }

  String get gitEmail => prefs.getString('git_email') ?? '';
  set gitEmail(String v) {
    prefs.setString('git_email', v);
    notifyListeners();
  }

  bool get crashReportingEnabled => prefs.getBool('crash_reporting_enabled') ?? true;
  set crashReportingEnabled(bool v) {
    prefs.setBool('crash_reporting_enabled', v);
    notifyListeners();
  }

  bool get wordWrap => prefs.getBool('word_wrap') ?? false;
  set wordWrap(bool v) {
    prefs.setBool('word_wrap', v);
    notifyListeners();
  }

  String get fontFamily => prefs.getString('font_family') ?? 'monospace';
  set fontFamily(String v) {
    prefs.setString('font_family', v);
    notifyListeners();
  }

  bool get showLineNumbers => prefs.getBool('show_line_numbers') ?? true;
  set showLineNumbers(bool v) {
    prefs.setBool('show_line_numbers', v);
    notifyListeners();
  }

  List<String> get primaryLanguages => prefs.getStringList('primary_languages') ?? [];
  set primaryLanguages(List<String> v) {
    prefs.setStringList('primary_languages', v);
    notifyListeners();
  }
}
