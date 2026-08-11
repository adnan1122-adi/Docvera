import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_service.dart';

/// Lifecycle of the app's single rewarded ad slot.
enum RewardedAdStatus {
  /// No ad requested yet (or the last one was consumed).
  idle,

  /// A load request is in flight.
  loading,

  /// An ad is loaded and ready to show.
  loaded,

  /// The ad is on screen.
  showing,

  /// The last load/show attempt failed. The slot is empty and can be retried.
  failed,
}

/// Owns the app's rewarded ad: load, show, reward, failure and reload.
///
/// Rewarded ads are expensive to build, so there is exactly one slot for the
/// whole app - never one per screen or per widget rebuild. The manager reloads
/// automatically after an ad is dismissed and when the app returns to the
/// foreground (full-screen ads expire and must be fetched again).
///
/// No product flow consumes a reward yet: this is pure infrastructure for the
/// upcoming premium decisions. Calling [load]/[show] is always safe; a missing
/// SDK or platform (web) is handled silently.
class RewardedAdManager with WidgetsBindingObserver {
  RewardedAdManager._();

  static final RewardedAdManager instance = RewardedAdManager._();

  /// Current state of the slot. Listen to repaint entitlement UI later.
  final ValueNotifier<RewardedAdStatus> status =
      ValueNotifier<RewardedAdStatus>(RewardedAdStatus.idle);

  RewardedAd? _ad;
  RewardItem? _lastReward;
  bool _observing = false;
  bool _disposed = false;

  /// The most recent reward earned (or null if none yet).
  RewardItem? get lastReward => _lastReward;

  /// Whether an ad is loaded and can be shown.
  bool get isLoaded => _ad != null;

  /// Registers for app-lifecycle events. Call once at startup (idempotent).
  void startObserving() {
    if (_observing || _disposed) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Loads a rewarded ad for the current platform. Safe to call anytime:
  /// no-ops while a load is already in flight or an ad is already ready.
  Future<void> load() async {
    if (_disposed || !AdConfig.isSupportedOnPlatform) return;
    final current = status.value;
    if (current == RewardedAdStatus.loading ||
        current == RewardedAdStatus.loaded ||
        current == RewardedAdStatus.showing) {
      return;
    }
    status.value = RewardedAdStatus.loading;
    try {
      await AdService.instance.initialize();
    } catch (_) {
      // SDK init is best-effort; the load below reports any failure.
    }
    if (_disposed) return;
    try {
      await RewardedAd.load(
        adUnitId: AdConfig.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              ad.dispose();
              return;
            }
            _ad = ad;
            status.value = RewardedAdStatus.loaded;
          },
          onAdFailedToLoad: (error) {
            _ad?.dispose();
            _ad = null;
            status.value = RewardedAdStatus.failed;
          },
        ),
      );
    } catch (_) {
      _ad = null;
      status.value = RewardedAdStatus.failed;
    }
  }

  /// Shows the loaded ad, if any. Returns the earned reward, or null when
  /// nothing was shown or no reward was granted.
  Future<RewardItem?> show() async {
    final ad = _ad;
    if (ad == null) return null;
    status.value = RewardedAdStatus.showing;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (dismissed) {
        dismissed.dispose();
        _ad = null;
        status.value = RewardedAdStatus.idle;
        // Prepare the next ad so the slot is ready when the user needs it.
        load();
      },
      onAdFailedToShowFullScreenContent: (failed, error) {
        failed.dispose();
        _ad = null;
        status.value = RewardedAdStatus.failed;
      },
    );
    try {
      await ad.show(onUserEarnedReward: (ad, reward) {
        _lastReward = reward;
      });
    } catch (_) {
      _ad = null;
      status.value = RewardedAdStatus.failed;
      return null;
    }
    return _lastReward;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Full-screen ads fetched before backgrounding may have expired.
      if (status.value != RewardedAdStatus.loaded &&
          status.value != RewardedAdStatus.loading) {
        load();
      }
    }
  }

  /// Releases the current ad and stops observing. Called on app teardown.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _ad?.dispose();
    _ad = null;
    status.dispose();
  }
}
