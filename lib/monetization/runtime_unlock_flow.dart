import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/di.dart';
import 'ad_service.dart';
import 'entitlement_service.dart';
import 'pro_paywall_sheet.dart';

export 'mission_banner.dart';

/// Checks if [runtimeId] is unlocked. If not, presents the Duolingo-style in-app
/// ad break banner with countdown timer, watery-eyes emoji, and Go Ad Free paywall link.
/// Returns true once unlocked.
Future<bool> ensureRuntimeUnlocked(
  BuildContext context, {
  required String runtimeId,
  required String runtimeTitle,
}) async {
  final entitlements = sl<EntitlementService>();
  if (entitlements.isRuntimeUnlocked(runtimeId)) {
    return true;
  }

  final unlocked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DuolingoAdUnlockSheet(
      runtimeId: runtimeId,
      title: runtimeTitle,
      actionLabel: 'Continue & Download $runtimeTitle',
    ),
  );

  return unlocked ?? false;
}

/// Checks if [extensionId] is unlocked. If not, presents the Duolingo-style in-app
/// ad break banner. If [runtimeId] is provided, unlocks both the extension and runtime.
/// Returns true once unlocked.
Future<bool> ensureExtensionUnlocked(
  BuildContext context, {
  required String extensionId,
  required String extensionTitle,
  String? runtimeId,
}) async {
  final entitlements = sl<EntitlementService>();
  if (entitlements.isExtensionUnlocked(extensionId)) {
    return true;
  }

  final unlocked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DuolingoAdUnlockSheet(
      extensionId: extensionId,
      runtimeId: runtimeId,
      title: extensionTitle,
      actionLabel: 'Continue & Install $extensionTitle',
    ),
  );

  return unlocked ?? false;
}

class DuolingoAdUnlockSheet extends StatefulWidget {
  final String? runtimeId;
  final String? extensionId;
  final String title;
  final String? actionLabel;
  final int initialCountdownSeconds;

  const DuolingoAdUnlockSheet({
    super.key,
    this.runtimeId,
    this.extensionId,
    String? runtimeTitle,
    String? title,
    this.actionLabel,
    this.initialCountdownSeconds = 6,
  }) : title = title ?? runtimeTitle ?? '';

  String get runtimeTitle => title;

  @override
  State<DuolingoAdUnlockSheet> createState() => _DuolingoAdUnlockSheetState();
}

class _DuolingoAdUnlockSheetState extends State<DuolingoAdUnlockSheet> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _adFailed = false;

  late int _remainingSeconds;
  bool _isUnlocked = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.initialCountdownSeconds;
    _startCountdown();
    _loadBannerAd();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _onRewardEarned();
      }
    });
  }

  Future<void> _onRewardEarned() async {
    final entitlements = sl<EntitlementService>();
    if (widget.runtimeId != null) {
      await entitlements.unlockRuntime(widget.runtimeId!);
    }
    if (widget.extensionId != null) {
      await entitlements.unlockExtension(widget.extensionId!);
    }
    if (!mounted) return;
    setState(() {
      _remainingSeconds = 0;
      _isUnlocked = true;
    });
  }

  void _loadBannerAd() {
    try {
      final adService = sl<AdService>();
      final banner = adService.createMediumRectangleAd(
        onAdLoaded: () {
          if (mounted) {
            setState(() {
              _isAdLoaded = true;
              _adFailed = false;
            });
          }
        },
        onAdFailedToLoad: (error) {
          if (mounted) {
            setState(() {
              _isAdLoaded = false;
              _adFailed = true;
            });
            // Fail open: grant unlock if ad cannot load offline
            _onRewardEarned();
          }
        },
      );

      if (banner != null) {
        _bannerAd = banner;
        banner.load();
      } else {
        // Non-mobile or test environment
        setState(() {
          _adFailed = true;
        });
        _onRewardEarned();
      }
    } catch (e) {
      debugPrint('Ad load exception: $e');
      setState(() {
        _adFailed = true;
      });
      _onRewardEarned();
    }
  }

  Future<void> _handleCloseTap() async {
    if (_isUnlocked) {
      Navigator.of(context).pop(true);
      return;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without unlocking?'),
        content: Text(
          'Wait $_remainingSeconds more seconds to unlock ${widget.runtimeTitle} offline permanently 🥺',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Watching'),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _handleGoAdFree() async {
    final boughtPro = await showProPaywallSheet(context);
    if (boughtPro && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10141D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF263342),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isUnlocked ? Icons.close_rounded : Icons.close_rounded,
                    color: _isUnlocked ? Colors.white : Colors.white60,
                  ),
                  tooltip: _isUnlocked ? 'Close and proceed' : 'Cancel ad',
                  onPressed: _handleCloseTap,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Advertising helps keep B Code free 🥺',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (!_isUnlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2330),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2D3C4F)),
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: const TextStyle(
                        color: Color(0xFF4FC3F7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(0xFF00E676), size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Unlocked',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 300,
                height: 250,
                decoration: BoxDecoration(
                  color: const Color(0xFF18202A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF263342)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildAdContent(),
              ),
            ),
            const SizedBox(height: 16),
            if (_isUnlocked)
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(widget.actionLabel ?? 'Continue & Download ${widget.title}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            if (_isUnlocked) const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                foregroundColor: const Color(0xFF00E676),
              ),
              onPressed: _handleGoAdFree,
              child: const Text(
                'GO AD FREE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdContent() {
    if (_isAdLoaded && _bannerAd != null) {
      return SizedBox(
        width: 300,
        height: 250,
        child: AdWidget(ad: _bannerAd!),
      );
    }

    if (_adFailed) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.volunteer_activism_rounded,
                color: Color(0xFF00E676),
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Supporting student coders',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sponsored ads offline. ${widget.title} unlocked for free so you keep building!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFF4FC3F7),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Loading sponsor ad…',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
