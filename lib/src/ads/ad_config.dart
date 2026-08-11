import 'package:flutter/foundation.dart';

/// Central advertising configuration.
///
/// Development / test ad unit IDs live here so the SDK never touches a
/// production ID during development. Production IDs are supplied at build
/// time with `--dart-define` and are NEVER hardcoded in the app:
///
/// ```sh
/// flutter run \
///   --dart-define=ADMOB_USE_PRODUCTION=true \
///   --dart-define=ADMOB_ANDROID_BANNER=<prod-banner-id> \
///   --dart-define=ADMOB_IOS_BANNER=<prod-banner-id>
/// ```
///
/// The app-level AdMob application IDs are still declared natively (see
/// AndroidManifest.xml and ios/Runner/Info.plist) because the mobile SDKs
/// read them before any Dart runs; replace the test IDs there for release.
abstract final class AdConfig {
  AdConfig._();

  /// Flip to `true` at build time to opt into production ad units.
  static const bool _useProduction =
      bool.fromEnvironment('ADMOB_USE_PRODUCTION');

  static const String _androidBannerProd =
      String.fromEnvironment('ADMOB_ANDROID_BANNER');
  static const String _iosBannerProd =
      String.fromEnvironment('ADMOB_IOS_BANNER');
  static const String _androidRewardedProd =
      String.fromEnvironment('ADMOB_ANDROID_REWARDED');
  static const String _iosRewardedProd =
      String.fromEnvironment('ADMOB_IOS_REWARDED');

  /// Google-provided TEST ad unit IDs (always used unless `_useProduction`).
  static const String androidBannerTestId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String iosBannerTestId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String androidRewardedTestId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosRewardedTestId =
      'ca-app-pub-3940256099942544/1712485313';

  /// Google-provided TEST application IDs (Android / iOS).
  static const String androidTestAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String iosTestAppId =
      'ca-app-pub-3940256099942544~1458002511';

  /// AdMob runs on mobile only; the web build never loads the native SDK.
  static bool get isSupportedOnPlatform => !kIsWeb;

  /// The banner ad unit id for the current platform (test during development).
  static String get bannerAdUnitId {
    if (_useProduction) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return _iosBannerProd;
      }
      return _androidBannerProd;
    }
    return defaultTargetPlatform == TargetPlatform.iOS
        ? iosBannerTestId
        : androidBannerTestId;
  }

  /// The rewarded ad unit id for the current platform (test during
  /// development). Rewarded ads are not wired into any flow yet.
  static String get rewardedAdUnitId {
    if (_useProduction) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return _iosRewardedProd;
      }
      return _androidRewardedProd;
    }
    return defaultTargetPlatform == TargetPlatform.iOS
        ? iosRewardedTestId
        : androidRewardedTestId;
  }
}
