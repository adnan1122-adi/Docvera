import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:pdf_editor/src/ads/ad_banner_view.dart';
import 'package:pdf_editor/src/ads/ad_config.dart';
import 'package:pdf_editor/src/ads/ad_service.dart';
import 'package:pdf_editor/src/ads/consent_manager.dart';
import 'package:pdf_editor/src/ads/monetization.dart';
import 'package:pdf_editor/src/ads/rewarded_ad_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdConfig', () {
    test('uses Google test ad unit IDs during development', () {
      // The VM test host reports macOS, so the non-iOS (Android) IDs apply.
      expect(AdConfig.isSupportedOnPlatform, isTrue);
      expect(AdConfig.bannerAdUnitId, AdConfig.androidBannerTestId);
      expect(AdConfig.rewardedAdUnitId, AdConfig.androidRewardedTestId);
      expect(
        AdConfig.bannerAdUnitId,
        isNot(contains('1-1-1')),
        reason: 'must never fall back to a fake production id',
      );
    });

    test('test ids are the official Google sample units', () {
      expect(AdConfig.androidBannerTestId,
          'ca-app-pub-3940256099942544/6300978111');
      expect(AdConfig.iosBannerTestId,
          'ca-app-pub-3940256099942544/2934735716');
      expect(AdConfig.androidRewardedTestId,
          'ca-app-pub-3940256099942544/5224354917');
      expect(AdConfig.iosRewardedTestId,
          'ca-app-pub-3940256099942544/1712485313');
    });
  });

  group('ConsentManager', () {
    test('debug builds grant consent without touching UMP', () async {
      final consent = ConsentManager(debug: true);
      expect(consent.mayRequestAds, isFalse);
      expect(await consent.ensureConsent(), isTrue);
      expect(consent.mayRequestAds, isTrue);
      expect(consent.status, ConsentStatus.obtained);
    });
  });

  group('EntitlementManager', () {
    test('free build unlocks every feature', () {
      const entitlements = FreeEntitlementManager();
      expect(entitlements.has(Entitlement.basic), isTrue);
      expect(entitlements.has(Entitlement.pro), isTrue);
    });
  });

  group('RewardedAdManager', () {
    test('is idle and cannot show before anything loads', () {
      expect(RewardedAdManager.instance.status.value, RewardedAdStatus.idle);
      expect(RewardedAdManager.instance.isLoaded, isFalse);
    });

    test('show() without an ad returns null', () async {
      expect(await RewardedAdManager.instance.show(), isNull);
    });

    test('load() fails closed when the SDK channel is missing', () async {
      await RewardedAdManager.instance.load();
      // The test host has no AdMob implementation: the slot must land in a
      // safe failed/idle state, never throw.
      expect(RewardedAdManager.instance.status.value,
          anyOf(RewardedAdStatus.failed, RewardedAdStatus.loaded));
      expect(RewardedAdManager.instance.isLoaded, isFalse);
    });
  });

  testWidgets('AdBannerView collapses to zero height when ads cannot load',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(height: 400, child: Placeholder()),
                AdBannerView(),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // No ad on screen and the slot takes no space - a failed or missing ad
      // must never push the app around.
      expect(find.byType(AdWidget), findsNothing);
      expect(tester.getSize(find.byType(AdBannerView)).height, 0);
    });
  });

  test('AdService is a supported singleton on mobile', () {
    final service = AdService.instance;
    expect(service.supported, isTrue);
    expect(service.entitlements.has(Entitlement.basic), isTrue);
  });
}
