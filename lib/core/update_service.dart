import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;

  const UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
  });
}

class UpdateService {
  static const String latestReleaseEndpoint =
      'https://api.github.com/repos/advaiti/b_code/releases/latest';

  final http.Client? _client;

  const UpdateService({http.Client? client}) : _client = client;

  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;
    } catch (_) {
      return '1.0.0+10';
    }
  }

  static bool isNewerVersion(String current, String latest) {
    final cleanCurrent = current.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final cleanLatest = latest.trim().replaceFirst(RegExp(r'^[vV]'), '');

    if (cleanCurrent.isEmpty || cleanLatest.isEmpty) return false;
    if (cleanCurrent == cleanLatest) return false;

    final currentParts = cleanCurrent.split('+');
    final latestParts = cleanLatest.split('+');

    final currentSemver =
        currentParts[0].split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final latestSemver =
        latestParts[0].split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLen = currentSemver.length > latestSemver.length
        ? currentSemver.length
        : latestSemver.length;

    for (var i = 0; i < maxLen; i++) {
      final cur = i < currentSemver.length ? currentSemver[i] : 0;
      final lat = i < latestSemver.length ? latestSemver[i] : 0;
      if (lat > cur) return true;
      if (lat < cur) return false;
    }

    final currentBuild =
        currentParts.length > 1 ? int.tryParse(currentParts[1]) : null;
    final latestBuild =
        latestParts.length > 1 ? int.tryParse(latestParts[1]) : null;

    if (currentBuild != null && latestBuild != null) {
      return latestBuild > currentBuild;
    }
    if (currentBuild == null && latestBuild != null) {
      return latestBuild > 0;
    }

    return false;
  }

  Future<UpdateInfo?> checkForUpdates({
    http.Client? client,
    String? currentVersion,
  }) async {
    final clientToUse = client ?? _client ?? http.Client();
    final shouldClose = client == null && _client == null;

    try {
      final response = await clientToUse.get(
        Uri.parse(latestReleaseEndpoint),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'BCode-Editor',
        },
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      final releaseUrl = (data['html_url'] as String?)?.trim() ??
          'https://github.com/advaiti/b_code/releases/latest';

      if (tagName.isEmpty) {
        return null;
      }

      final curVer = currentVersion ?? await getCurrentVersion();
      final hasUpdate = isNewerVersion(curVer, tagName);

      return UpdateInfo(
        hasUpdate: hasUpdate,
        currentVersion: curVer,
        latestVersion: tagName,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) {
        clientToUse.close();
      }
    }
  }

  Future<void> showUpdateDialog(
    BuildContext context, {
    required String releaseUrl,
    required String latestVersion,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: const Text(
          'New B Code update available! Tap to download the latest compilers and fixes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.parse(releaseUrl);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                await launchUrl(uri);
              }
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> checkAndPrompt(
    BuildContext context, {
    bool showFeedback = true,
    http.Client? client,
  }) async {
    if (showFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking for updates...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final updateInfo = await checkForUpdates(client: client);
    if (!context.mounted) return;

    if (updateInfo != null && updateInfo.hasUpdate) {
      await showUpdateDialog(
        context,
        releaseUrl: updateInfo.releaseUrl,
        latestVersion: updateInfo.latestVersion,
      );
    } else if (showFeedback) {
      final versionText = updateInfo?.currentVersion.isNotEmpty == true
          ? ' (v${updateInfo!.currentVersion.split('+').first})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('B Code is up to date$versionText.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
