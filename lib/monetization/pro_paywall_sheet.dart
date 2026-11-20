import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/di.dart';
import '../core/haptics.dart';
import 'device_id_provider.dart';
import 'entitlement_service.dart';

/// Shows a Duolingo Super inspired contextual paywall for B Code Pro.
Future<bool> showProPaywallSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const ProPaywallSheet(),
  );
  return result ?? false;
}

Future<bool?> showLicenseInputDialog(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      String? errorText;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF30363D)),
            ),
            title: const Row(
              children: [
                Icon(Icons.key_rounded, color: Color(0xFF00E676), size: 22),
                SizedBox(width: 8),
                Text(
                  'Enter License Key',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste your Pro license key (starts with BCODE.) to activate offline:',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'BCODE.payload.signature',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    errorText: errorText,
                    errorMaxLines: 2,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF00E676)),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final text = controller.text.replaceAll(RegExp(r'\s+'), '');
                  if (text.isEmpty) {
                    setState(() => errorText = 'Please paste your license key');
                    return;
                  }
                  if (sl.isRegistered<EntitlementService>()) {
                    final entitlements = sl<EntitlementService>();
                    final result = await entitlements.activateWithLicenseKey(text);
                    if (result.isValid) {
                      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🎉 Kriya Pro activated! All features unlocked.'),
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                      return;
                    }
                    setState(() => errorText = result.errorMessage ?? 'Invalid or corrupted license key');
                    return;
                  }
                  setState(() => errorText = 'Licensing service unavailable');
                },
                child: const Text('Activate', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String> _getProActiveTitle() async {
  try {
    String? key;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        const storage = FlutterSecureStorage();
        key = await storage.read(key: 'bcode_license_key');
      } catch (_) {}
    }
    if (key == null || key.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      key = prefs.getString('bcode_license_key');
    }
    if (key != null && key.isNotEmpty) {
      final clean = key.replaceAll(RegExp(r'\s+'), '');
      final parts = clean.split('.');
      if (parts.length == 3 && parts[0] == 'BCODE') {
        final payloadBytes = base64Url.decode(base64.normalize(parts[1]));
        final payload = utf8.decode(payloadBytes);
        final components = payload.split(':');
        if (components.length >= 3 && components[2].isNotEmpty) {
          return 'Kriya Pro Active (Semester Pass)';
        }
        return 'Kriya Pro Active (Lifetime Pass)';
      }
    }
  } catch (_) {}
  return 'Kriya Pro Active (Semester Pass)';
}

class ProPaywallSheet extends StatefulWidget {
  const ProPaywallSheet({super.key});

  @override
  State<ProPaywallSheet> createState() => _ProPaywallSheetState();
}

class _ProPaywallSheetState extends State<ProPaywallSheet> {
  late final Future<String> _proTitleFuture;

  @override
  void initState() {
    super.initState();
    _proTitleFuture = _getProActiveTitle();
  }

  Future<void> _openPaymentModal(BuildContext context) async {
    Haptics.light();
    final unlocked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const UpiScanPaySheet(),
    );
    if (unlocked == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _enterLicenseKey(BuildContext context) async {
    Haptics.light();
    final unlocked = await showLicenseInputDialog(context);
    if (unlocked == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entitlements = sl.isRegistered<EntitlementService>() ? sl<EntitlementService>() : null;
    final isAlreadyPro = entitlements?.isRuntimeUnlocked('') ?? false;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF2A364F),
          width: 1,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF388E3C), Color(0xFF00E676)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, color: Colors.black, size: 18),
                      SizedBox(width: 4),
                      Text(
                        'B CODE PRO',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Code with zero interruptions',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The Semester Pass for mobile coding with zero ads, unlimited cloud builds, and instant compiler downloads.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              const _FeatureMatrix(),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '₹49 / 6 MONTHS',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'The Semester Pass (~₹8/month)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'SEMESTER PASS',
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (isAlreadyPro) ...[
                FutureBuilder<String>(
                  future: _proTitleFuture,
                  builder: (context, snapshot) {
                    final title = snapshot.data ?? 'Kriya Pro Active (Semester Pass)';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_rounded, color: Color(0xFF00E676), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset to Free Tier (For Testing)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    Haptics.light();
                    await entitlements?.setProTier(false);
                    if (context.mounted) {
                      Navigator.of(context).pop(false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Switched back to Free Tier for testing.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
              ] else ...[
                FutureBuilder<String>(
                  future: DeviceIdProvider.getDeviceId(),
                  builder: (context, snapshot) {
                    final deviceId = snapshot.data ?? '...';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF21262D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.smartphone_rounded, size: 16, color: Color(0xFF00E676)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'YOUR DEVICE ID (KEYS ARE LOCKED TO THIS PHONE)',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                Text(
                                  deviceId,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(text: deviceId));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Device ID copied to clipboard!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.copy_rounded, size: 14, color: Color(0xFF00E676)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  label: const Text('Scan QR Code & Pay ₹49'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  onPressed: () => _openPaymentModal(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Enter License Key'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: () => _enterLicenseKey(context),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Keep Kriya free with ads',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dedicated Scan & Pay modal designed specifically for single-phone and two-phone payments.
class UpiScanPaySheet extends StatelessWidget {
  const UpiScanPaySheet({super.key});

  Future<void> _copyUpiId(BuildContext context) async {
    Haptics.light();
    await Clipboard.setData(const ClipboardData(text: AppConstants.proUpiId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UPI ID copied! Open GPay, PhonePe, or Paytm and paste to pay ₹49.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _openTelegram(BuildContext context) async {
    Haptics.light();
    final deviceId = await DeviceIdProvider.getDeviceId();
    final message = Uri.encodeComponent(
      'Hi Aditya, I paid ₹49 for Kriya Pro (6-Month Semester Pass).\n'
      '- UPI UTR: [paste your 12-digit UTR here]\n'
      '- Device ID: $deviceId',
    );
    final uri = Uri.parse('https://t.me/${AppConstants.proTelegramUsername}?text=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Telegram. Message @bakadev directly.'),
        ),
      );
    }
  }

  Future<void> _enterLicenseKey(BuildContext context) async {
    Haptics.light();
    final unlocked = await showLicenseInputDialog(context);
    if (unlocked == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.94,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF2A364F),
          width: 1,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00E676), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Scan & Pay ₹49',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Single-Device Instruction Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F293D),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF4FC3F7).withValues(alpha: 0.3),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.smartphone_rounded, color: Color(0xFF4FC3F7), size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Paying on this phone? (No 2nd phone needed)',
                          style: TextStyle(
                            color: Color(0xFF4FC3F7),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      '1. Pay ₹49 using QR or "Copy UPI ID" below.\n'
                      '2. Tap "Send UTR & Device ID via Telegram".\n'
                      '3. Aditya verifies and sends your key on Telegram.\n'
                      '4. Tap "Enter License Key & Unlock Pro" to activate.',
                      style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: DeviceIdProvider.getDeviceId(),
                builder: (context, snapshot) {
                  final deviceId = snapshot.data ?? '...';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF21262D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.smartphone_rounded, size: 16, color: Color(0xFF00E676)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'YOUR DEVICE ID (LOCKED TO THIS PHONE)',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                deviceId,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: deviceId));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Device ID copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.copy_rounded, size: 14, color: Color(0xFF00E676)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              // QR Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/images/pro_qr.png',
                          width: 160,
                          height: 160,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => _copyUpiId(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF21262D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF30363D)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'UPI: ${AppConstants.proUpiId}',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.copy_rounded, size: 14, color: Color(0xFF00E676)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Or scan using another device camera',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    const Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _UpiBadge('Google Pay'),
                        _UpiBadge('PhonePe'),
                        _UpiBadge('Paytm'),
                        _UpiBadge('BHIM'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Reassurance note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.white54, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Safe to switch apps. You can reopen this screen anytime to unlock.',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy UPI ID'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onPressed: () => _copyUpiId(context),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send UTR & Device ID via Telegram'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF229ED9),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onPressed: () => _openTelegram(context),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                icon: const Icon(Icons.key_rounded, size: 18),
                label: const Text('Enter License Key & Unlock Pro'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onPressed: () => _enterLicenseKey(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpiBadge extends StatelessWidget {
  final String label;

  const _UpiBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FeatureMatrix extends StatelessWidget {
  const _FeatureMatrix();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B262C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00E676).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFF00E676), size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Pro Semester Pass (₹49 / 6 Months)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _FeatureItem(text: '⚡ 100% Zero Ads across the entire app'),
              const SizedBox(height: 8),
              const _FeatureItem(text: '🚀 Unlimited GitHub Cloud Builds & 1-Tap APK Install'),
              const SizedBox(height: 8),
              const _FeatureItem(text: '✨ Auto-Format on Save (Prettier, Clang-Format, Black)'),
              const SizedBox(height: 8),
              const _FeatureItem(text: '🌐 Local Wi-Fi Live Web Dev Server (Share with friends)'),
              const SizedBox(height: 8),
              const _FeatureItem(text: '⚡ Instant 1-Tap Compiler Downloads (No sponsor countdown)'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A364F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.school_rounded, color: Color(0xFF4FC3F7), size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Free Forever (Student Guarantee)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'FREE',
                      style: TextStyle(
                        color: Color(0xFF4FC3F7),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _FeatureItem(
                text: 'All Languages: C, C++, Python, Java, Web',
                icon: Icons.check_circle_outline_rounded,
                iconColor: Color(0xFF4FC3F7),
              ),
              const SizedBox(height: 8),
              const _FeatureItem(
                text: 'Offline Syntax Highlighting & Autocomplete',
                icon: Icons.check_circle_outline_rounded,
                iconColor: Color(0xFF4FC3F7),
              ),
              const SizedBox(height: 8),
              const _FeatureItem(
                text: 'Local Code Execution & Terminal',
                icon: Icons.check_circle_outline_rounded,
                iconColor: Color(0xFF4FC3F7),
              ),
              const SizedBox(height: 8),
              const _FeatureItem(
                text: '2 GitHub Cloud Builds per day',
                icon: Icons.check_circle_outline_rounded,
                iconColor: Color(0xFF4FC3F7),
              ),
              const SizedBox(height: 8),
              const _FeatureItem(
                text: '5-Second Sponsor Break before runtime downloads',
                icon: Icons.timer_outlined,
                iconColor: Colors.white54,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;

  const _FeatureItem({
    required this.text,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor ?? const Color(0xFF00E676), size: 16),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
