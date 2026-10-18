import 'package:flutter/services.dart';

class Haptics {
  static const _light = HapticFeedback.lightImpact;
  static const _medium = HapticFeedback.mediumImpact;
  static const _heavy = HapticFeedback.heavyImpact;
  static const _selection = HapticFeedback.selectionClick;
  static const _vibrate = HapticFeedback.vibrate;

  static Future<void> light() => _light();
  static Future<void> medium() => _medium();
  static Future<void> heavy() => _heavy();
  static Future<void> selection() => _selection();
  static Future<void> vibrate() => _vibrate();

  static Future<void> onTabClose() => _light();
  static Future<void> onTabSwitch() => _selection();
  static Future<void> onSave() => _light();
  static Future<void> onRun() => _medium();
  static Future<void> onError() => _heavy();
  static Future<void> onSuccess() => _light();
  static Future<void> onKeyPress() => _selection();
}