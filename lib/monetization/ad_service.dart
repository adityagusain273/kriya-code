import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdOutcome {
  earnedReward,
  failedGracefully,
  adBlocked,
  cancelled,
}

abstract class AdService {
  Future<void> initialize();
  void preloadRewardedAd();
  bool get isAdReady;
  Future<AdOutcome> showRewardedAd({
    required BuildContext context,
    required String runtimeTitle,
  });
  BannerAd? createMediumRectangleAd({
    required void Function() onAdLoaded,
    required void Function(LoadAdError error) onAdFailedToLoad,
  });
}

class AdMobAdService implements AdService {
  // Google's official sample rewarded ad unit ID for Android (safe for debug)
  static const String testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  // Production AdMob Rewarded Ad Unit ID for B Code
  static const String prodRewardedAdUnitId =
      'ca-app-pub-1244539971368385/2472379302';

  // Google's official sample banner / MREC ad unit ID for Android (safe for debug)
  static const String testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  // Production AdMob Banner Ad Unit ID for B Code
  static const String prodBannerAdUnitId =
      'ca-app-pub-1244539971368385/3664227388';

  final String rewardedAdUnitId;
  final String bannerAdUnitId;
  RewardedAd? _preloadedAd;
  bool _isLoading = false;

  AdMobAdService({
    String? rewardedAdUnitId,
    String? bannerAdUnitId,
  })  : rewardedAdUnitId = rewardedAdUnitId ??
            const String.fromEnvironment(
              'ADMOB_REWARDED_AD_UNIT_ID',
              defaultValue:
                  kReleaseMode ? prodRewardedAdUnitId : testRewardedAdUnitId,
            ),
        bannerAdUnitId = bannerAdUnitId ??
            const String.fromEnvironment(
              'ADMOB_BANNER_AD_UNIT_ID',
              defaultValue:
                  kReleaseMode ? prodBannerAdUnitId : testBannerAdUnitId,
            );

  @override
  BannerAd? createMediumRectangleAd({
    required void Function() onAdLoaded,
    required void Function(LoadAdError error) onAdFailedToLoad,
  }) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return null;
    }
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.mediumRectangle,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => onAdLoaded(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob MREC banner load failed: ${error.message} (code ${error.code})');
          ad.dispose();
          onAdFailedToLoad(error);
        },
      ),
    );
  }

  @override
  bool get isAdReady => _preloadedAd != null;

  @override
  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await MobileAds.instance.initialize();
      preloadRewardedAd();
    } catch (e) {
      debugPrint('AdMob initialization error: $e');
    }
  }

  @override
  void preloadRewardedAd() {
    if (_preloadedAd != null || _isLoading) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    _isLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _preloadedAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _preloadedAd = null;
          _isLoading = false;
          debugPrint('AdMob preload failed: ${error.message} (code ${error.code})');
        },
      ),
    );
  }

  Future<bool> _isAdBlockerActive() async {
    if (kIsWeb) return false;
    try {
      const adHosts = [
        'googleads.g.doubleclick.net',
        'pagead2.googlesyndication.com',
      ];
      for (final host in adHosts) {
        final addrs = await InternetAddress.lookup(host)
            .timeout(const Duration(milliseconds: 1500));
        if (addrs.isEmpty) return true;
        for (final addr in addrs) {
          if (addr.address == '0.0.0.0' || addr.address == '127.0.0.1') {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      try {
        final general = await InternetAddress.lookup('google.com')
            .timeout(const Duration(milliseconds: 1500));
        if (general.isNotEmpty) {
          return true;
        }
      } catch (_) {
        return false;
      }
      return false;
    }
  }

  @override
  Future<AdOutcome> showRewardedAd({
    required BuildContext context,
    required String runtimeTitle,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return AdOutcome.earnedReward;
    }

    RewardedAd? ad = _preloadedAd;
    if (ad == null) {
      // Ad is not preloaded yet; show brief loader and wait up to 6s
      if (!context.mounted) return AdOutcome.cancelled;

      final loadCompleter = Completer<RewardedAd?>();
      var dismissedByTimeout = false;

      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => AlertDialog(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Loading sponsor video…',
                  style: Theme.of(dialogCtx).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                dismissedByTimeout = true;
                Navigator.of(dialogCtx).pop();
                if (!loadCompleter.isCompleted) loadCompleter.complete(null);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (loadedAd) {
            if (!loadCompleter.isCompleted) loadCompleter.complete(loadedAd);
          },
          onAdFailedToLoad: (error) {
            debugPrint('AdMob ad load failed: ${error.message}');
            if (!loadCompleter.isCompleted) loadCompleter.complete(null);
          },
        ),
      );

      final timer = Timer(const Duration(seconds: 6), () {
        if (!loadCompleter.isCompleted) loadCompleter.complete(null);
      });

      ad = await loadCompleter.future;
      timer.cancel();

      if (context.mounted && !dismissedByTimeout) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (dismissedByTimeout) {
        ad?.dispose();
        preloadRewardedAd();
        return AdOutcome.cancelled;
      }
    }

    if (ad == null) {
      final isBlocked = await _isAdBlockerActive();
      preloadRewardedAd();
      if (isBlocked) {
        return AdOutcome.adBlocked;
      }
      return AdOutcome.failedGracefully;
    }

    final resultCompleter = Completer<AdOutcome>();
    var userEarnedReward = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (adInstance) {
        adInstance.dispose();
        _preloadedAd = null;
        preloadRewardedAd();
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(
            userEarnedReward ? AdOutcome.earnedReward : AdOutcome.cancelled,
          );
        }
      },
      onAdFailedToShowFullScreenContent: (adInstance, error) {
        adInstance.dispose();
        _preloadedAd = null;
        preloadRewardedAd();
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(AdOutcome.failedGracefully);
        }
      },
    );

    ad.show(
      onUserEarnedReward: (adWithoutView, reward) {
        userEarnedReward = true;
      },
    );

    return resultCompleter.future;
  }
}
