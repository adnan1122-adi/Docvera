import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'consent_manager.dart';
import 'monetization.dart';
import 'rewarded_ad_manager.dart';

/// Central AdMob entry point for the app.
///
/// Screens never talk to the plugin directly: they ask this service for a
/// banner and render it through [AdBannerView]. The service owns SDK init,
/// consent gating, entitlement checks, and the active-banner bookkeeping that
/// lets slots expand and collapse together.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  final ConsentManager _consent = ConsentManager();
  final EntitlementManager _entitlements = const FreeEntitlementManager();
  final RewardedAdManager _rewarded = RewardedAdManager.instance;

  bool _initialized = false;

  /// Number of banners currently loaded and on screen (>= 0). Listen to this
  /// to show/hide ad slots as a group.
  final ValueNotifier<int> activeBanners = ValueNotifier<int>(0);

  ConsentManager get consent => _consent;

  EntitlementManager get entitlements => _entitlements;

  /// Rewarded ad infrastructure (not consumed by any flow yet).
  RewardedAdManager get rewarded => _rewarded;

  /// Whether this build supports ads at all (mobile only - never web).
  bool get supported => AdConfig.isSupportedOnPlatform;

  /// Whether an ad slot may currently be filled (supported + consent).
  bool get shouldShowBanner => supported && _consent.mayRequestAds;

  /// Initializes the SDK (consent + AdMob) once. Idempotent; safe to call
  /// from `main()` and again from individual slots. Never throws: ads are
  /// optional, so any SDK problem just leaves slots collapsed.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!supported) return;
    _rewarded.startObserving();
    // Run inside a guarded zone: the plugin's `MobileAds.instance` fires an
    // unawaited `_init` channel call, which surfaces as an unhandled error on
    // platforms without the SDK (unit tests, broken channels). Ads are
    // optional, so any such failure is swallowed - never a crash or a block.
    await runZonedGuarded(() async {
      try {
        await _consent.ensureConsent();
        await MobileAds.instance.initialize();
      } catch (_) {
        // No consent / no SDK / platform channel missing (e.g. unit tests).
      }
    }, (Object _, StackTrace _) {
      // Swallow unawaited SDK errors; slots simply stay collapsed.
    });
  }

  /// Creates (and starts loading) a banner for a slot, or null when ads are
  /// gated (web, no consent, or not yet initialized).
  BannerAd? createBannerAd(
    AdSize size, {
    required BannerAdListener listener,
  }) {
    if (!shouldShowBanner) return null;
    final banner = BannerAd(
      size: size,
      adUnitId: AdConfig.bannerAdUnitId,
      listener: listener,
      request: const AdRequest(),
    );
    // Loading is fire-and-forget; a failure to reach the platform channel or
    // the SDK simply keeps the slot collapsed (the listener sees onAdFailed).
    banner.load().catchError((Object _) {});
    return banner;
  }

  /// Records that a banner successfully loaded, expanding its slot.
  void onBannerLoaded(Ad banner) {
    activeBanners.value++;
  }

  /// Releases the platform resources for [banner] and collapses any slot that
  /// depended on it. Calling with null (a slot was never created) is a no-op.
  void disposeBannerAd(BannerAd? banner) {
    final b = banner;
    if (b == null) return;
    b.dispose();
    if (activeBanners.value > 0) {
      activeBanners.value--;
    }
  }
}