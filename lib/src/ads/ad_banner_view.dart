import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// A banner ad slot.
///
/// Renders nothing on web, stays collapsed (zero height) while loading and on
/// failure, and only occupies space once an ad actually loads - so a missing
/// or failed ad never pushes the PDF canvas around or blanks the layout.
///
/// Every request goes through [AdService] so consent, entitlements and support
/// are enforced centrally. Failures are silent: the surrounding screen is
/// never blocked and no errors or dialogs are shown.
class AdBannerView extends StatefulWidget {
  const AdBannerView({super.key});

  @override
  State<AdBannerView> createState() => _AdBannerViewState();
}

class _AdBannerViewState extends State<AdBannerView> {
  final AdService _service = AdService.instance;

  BannerAd? _ad;
  bool _loaded = false;
  bool _started = false;

  @override
  void dispose() {
    _service.disposeBannerAd(_ad);
    super.dispose();
  }

  Future<void> _load(double width) async {
    try {
      await _service.initialize();
      if (!mounted) return;
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        math.max(320, width.round()),
      ) ??
          const AdSize(width: 320, height: 50);
      if (!mounted) return;
      final ad = _service.createBannerAd(
        size,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            _service.onBannerLoaded(ad);
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            // Release the failed ad and keep the slot collapsed. The app
            // continues normally; a missing ad never blocks anything.
            ad.dispose();
            if (mounted) {
              setState(() {
                _ad = null;
                _loaded = false;
              });
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() => _ad = ad);
    } catch (_) {
      // SDK/platform unavailable or a load failed - keep the slot collapsed.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.supported) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width > 0 && !_started) {
          _started = true;
          _load(width);
        }
        final ad = _ad;
        if (ad != null && _loaded) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(height: 1),
              SizedBox(
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ],
          );
        }
        // Loading, consent-gated, or failed: collapse to nothing.
        return const SizedBox.shrink();
      },
    );
  }
}