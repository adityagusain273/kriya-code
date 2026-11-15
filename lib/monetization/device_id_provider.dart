import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class DeviceIdProvider {
  static const _channel = MethodChannel('bcode.integrity');
  static String? _cachedId;

  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return 'BCODE-DEV-LOCAL';
      }
      final id = await _channel.invokeMethod<String>('deviceId');
      if (id != null && id.isNotEmpty) {
        _cachedId = id;
        return id;
      }
    } catch (_) {}
    return 'BCODE-DEV-LOCAL';
  }

  static void setMockDeviceId(String? id) {
    _cachedId = id;
  }
}
