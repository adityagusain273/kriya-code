import 'package:flutter/services.dart';

class DeviceIdProvider {
  static const _channel = MethodChannel('bcode.integrity');
  static String? _cachedId;

  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    try {
      final id = await _channel
          .invokeMethod<String>('deviceId')
          .timeout(const Duration(milliseconds: 100));
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
