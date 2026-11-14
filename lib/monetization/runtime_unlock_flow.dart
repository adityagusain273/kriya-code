import 'package:flutter/material.dart';

import '../core/di.dart';
import 'ad_service.dart';
import 'entitlement_service.dart';
import 'pro_paywall_sheet.dart';

/// Checks if [runtimeId] is unlocked. If not, prompts the user with a Duolingo-style
/// sponsor sheet to watch a rewarded video or go ad-free. Returns true if unlocked.
Future<bool> ensureRuntimeUnlocked(
  BuildContext context, {
  required String runtimeId,
  required String runtimeTitle,
}) async {
  final entitlements = sl<EntitlementService>();
  if (entitlements.isRuntimeUnlocked(runtimeId)) {
    return true;
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UnlockPromptSheet(
      runtimeTitle: runtimeTitle,
    ),
  );

  if (!context.mounted) return false;

  if (choice == 'pro') {
    final boughtPro = await showProPaywallSheet(context);
    if (boughtPro) return true;
    if (!context.mounted) return false;
  } else if (choice == 'watch') {
    final adService = sl<AdService>();
    final outcome = await adService.showRewardedAd(
      context: context,
      runtimeTitle: runtimeTitle,
    );

    if (!context.mounted) return false;

    switch (outcome) {
      case AdOutcome.earnedReward:
        await entitlements.unlockRuntime(runtimeId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$runtimeTitle unlocked forever!'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;

      case AdOutcome.failedGracefully:
        await entitlements.unlockRuntime(runtimeId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sponsored ad unavailable — $runtimeTitle unlocked for free!'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return true;

      case AdOutcome.adBlocked:
        if (context.mounted) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.shield_outlined, color: Colors.amber, size: 36),
              title: const Text('Ad Blocker Detected'),
              content: const Text(
                'B Code is completely free for students and devs, supported by short sponsored ads.\n\n'
                'Please temporarily turn off your ad blocker or private DNS '
                '(such as AdGuard or NextDNS) in device settings to unlock this compiler runtime.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Got It'),
                ),
              ],
            ),
          );
        }
        return false;

      case AdOutcome.cancelled:
        return false;
    }
  }

  return false;
}

class _UnlockPromptSheet extends StatelessWidget {
  final String runtimeTitle;

  const _UnlockPromptSheet({required this.runtimeTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF2A364F),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
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
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const Expanded(
                  child: Text(
                    'Advertising helps keep B Code free',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 24), // Balance the close button
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2232),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A364F)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.ondemand_video_rounded,
                      color: Color(0xFF00E676),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Unlock $runtimeTitle Offline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Watch one short 15–30s sponsor video to unlock this compiler on your phone forever. Zero banner ads inside your editor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.play_circle_filled_rounded),
              label: const Text('Watch Sponsor Ad & Unlock'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
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
              onPressed: () => Navigator.of(context).pop('watch'),
            ),
            const SizedBox(height: 10),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                foregroundColor: const Color(0xFF00E676),
              ),
              onPressed: () => Navigator.of(context).pop('pro'),
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
}
