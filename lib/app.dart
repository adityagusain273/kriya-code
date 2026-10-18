import 'package:flutter/material.dart';

import 'editor/editor_page.dart';
import 'onboarding/onboarding_page.dart';
import 'settings/settings_store.dart';

class BCodeApp extends StatelessWidget {
  final SettingsStore settings;

  const BCodeApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        title: 'B Code',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4FC3F7)),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4FC3F7),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: settings.onboardingComplete
            ? const EditorPage()
            : const OnboardingPage(),
      ),
    );
  }
}
