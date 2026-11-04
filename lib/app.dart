import 'package:flutter/material.dart';

import 'editor/editor_page.dart';
import 'onboarding/onboarding_page.dart';
import 'settings/settings_store.dart';

class BCodeApp extends StatelessWidget {
  final SettingsStore settings;

  const BCodeApp({super.key, required this.settings});

  /// Built once. `ColorScheme.fromSeed` is the Material colour algorithm, and
  /// regenerating both schemes on every settings notification made dragging the
  /// font-size slider stutter.
  static final ThemeData _lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4FC3F7)),
    useMaterial3: true,
    fontFamily: 'Roboto',
  );

  static final ThemeData _darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4FC3F7),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        title: 'B Code',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        home: settings.onboardingComplete
            ? const EditorPage()
            : const OnboardingPage(),
      ),
    );
  }
}
