import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class CrashReporter {
  static File? _logFile;
  static const _maxLogBytes = 100 * 1024;

  static final _sensitivePatterns = [
    RegExp(r'ghp_[A-Za-z0-9]{36}', caseSensitive: false),
    RegExp(r'gho_[A-Za-z0-9]{36}', caseSensitive: false),
    RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
    RegExp(r'Authorization:\s*Bearer\s+[^\s]+', caseSensitive: false),
    RegExp(r'client_secret=[^\s&]+', caseSensitive: false),
    RegExp(r'access_token[=:]\s*[^\s&"]+', caseSensitive: false),
  ];

  static String _redact(String message) {
    var result = message;
    for (final pattern in _sensitivePatterns) {
      result = result.replaceAll(pattern, '[REDACTED]');
    }
    return result;
  }

  static Future<void> init({bool enabled = true}) async {
    FlutterError.onError = (details) {
      final msg = _redact('${details.exceptionAsString()}\n${details.stack}');
      _log('FLUTTER ERROR', msg);
      if (kDebugMode) FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      final msg = _redact('$error\n$stack');
      _log('PLATFORM ERROR', msg);
      return true;
    };
  }

  static Future<void> setCollectionEnabled(bool enabled) async {}

  static void recordZoneError(Object error, StackTrace stack) {
    final msg = _redact('$error\n$stack');
    _log('ZONE ERROR', msg);
  }

  static Future<void> setUserId(String id) async {}

  static Future<void> setCustomKey(String key, String value) async {}

  static Future<void> log(String message) async {}

  static Future<void> _log(String type, String message) async {
    try {
      _logFile ??= await _getFile();
      await _rotateIfNeeded(_logFile!);
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!.writeAsString(
        '[$timestamp] $type\n$message\n${'─' * 60}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static Future<void> _rotateIfNeeded(File file) async {
    try {
      if (await file.exists()) {
        final size = await file.length();
        if (size > _maxLogBytes) {
          final content = await file.readAsString();
          final keepFrom = content.length - (_maxLogBytes ~/ 2);
          final newContent = content.substring(keepFrom.clamp(0, content.length));
          await file.writeAsString('--- LOG ROTATED ($size bytes trimmed) ---\n$newContent');
        }
      }
    } catch (_) {}
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/crash.log');
  }

  static Future<String> readLog() async {
    try {
      _logFile ??= await _getFile();
      if (await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (_) {}
    return '';
  }

  static Future<void> clearLog() async {
    try {
      _logFile ??= await _getFile();
      if (await _logFile!.exists()) {
        await _logFile!.delete();
      }
      _logFile = null;
    } catch (_) {}
  }

  static Future<Map<String, String>> collectDeviceInfo() async {
    final info = <String, String>{};
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        info['device'] = '${android.manufacturer} ${android.model}';
        info['os'] = 'Android ${android.version.release}';
        info['sdk'] = '${android.version.sdkInt}';
        info['brand'] = android.brand;
        info['product'] = android.product;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        info['device'] = '${ios.name} ${ios.model}';
        info['os'] = 'iOS ${ios.systemVersion}';
      }
    } catch (_) {}
    info['app_version'] = '1.0.0';
    info['platform'] = Platform.operatingSystem;
    return info;
  }

  static Future<String> buildBugReport({String? userMessage}) async {
    final buffer = StringBuffer();
    buffer.writeln('=== B Code Bug Report ===');
    buffer.writeln('Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    if (userMessage != null && userMessage.isNotEmpty) {
      buffer.writeln('User Description: $userMessage');
      buffer.writeln();
    }

    buffer.writeln('--- Device Info ---');
    final deviceInfo = await collectDeviceInfo();
    for (final entry in deviceInfo.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    final log = await readLog();
    if (log.isNotEmpty) {
      buffer.writeln('--- Crash Log (last 4KB) ---');
      final start = log.length > 4096 ? log.length - 4096 : 0;
      buffer.writeln(log.substring(start));
    }

    return buffer.toString();
  }

  static Future<void> submitBugReport({String? userMessage}) async {
    final reportBody = await buildBugReport(userMessage: userMessage);
    
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'adityagusain273@gmail.com',
      query: 'subject=B Code Bug Report / Feedback&body=${Uri.encodeComponent(reportBody)}\n\n(Please attach any screenshots here if applicable)',
    );

    try {
      // Note: requires import 'package:url_launcher/url_launcher.dart'; 
      // We will add the import at the top of the file
      await launchUrl(emailLaunchUri);
    } catch (e) {
      _log('EMAIL ERROR', 'Could not launch email client: $e');
    }
  }
}