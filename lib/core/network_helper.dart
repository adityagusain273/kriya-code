import 'dart:io';

class NetworkHelper {
  /// Lightweight reachability check.
  ///
  /// Previously this looked up `google.com` on every call, which both leaked the
  /// user's IP to Google's resolver whenever the app asked "am I online?" and
  /// was not actually a connectivity test (DNS can resolve with no usable route).
  static Future<bool> get isOnline async {
    try {
      final result = await InternetAddress.lookup('github.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
