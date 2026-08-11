import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps the Google User Messaging Platform (UMP) consent flow.
///
/// Advertising may only start once [mayRequestAds] is true. The flow is
/// best-effort: a privacy-form failure must never block or break the app, so
/// the SDK is simply left without ads and banner slots stay collapsed.
///
/// In debug builds consent is granted immediately without touching UMP, so
/// development on a fresh install never stalls on a privacy form.
class ConsentManager {
  ConsentManager({this.debug = kDebugMode});

  /// When true (the default in debug builds), consent is granted immediately
  /// without touching UMP so development never stalls on a privacy form.
  final bool debug;

  bool _initialized = false;
  bool _mayRequestAds = false;
  ConsentStatus _status = ConsentStatus.unknown;
  FormError? _error;

  /// True once [ensureConsent] has finished (any outcome).
  bool get initialized => _initialized;

  /// True when the SDK may request ads.
  bool get mayRequestAds => _mayRequestAds;

  /// Latest UMP status; stays [ConsentStatus.unknown] before UMP runs.
  ConsentStatus get status => _status;

  /// The last consent failure, if any. Non-fatal: bannners simply collapse.
  FormError? get error => _error;

  /// Runs the consent flow once. Idempotent; resolves to [mayRequestAds].
  Future<bool> ensureConsent() async {
    if (_initialized) return _mayRequestAds;
    _initialized = true;

    if (debug) {
      // Development build - skip UMP entirely so ads always flow for tests.
      _mayRequestAds = true;
      _status = ConsentStatus.obtained;
      return _mayRequestAds;
    }

    final completer = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await _onConsentInfoUpdated();
        if (!completer.isCompleted) completer.complete(_mayRequestAds);
      },
      (error) {
        _error = error;
        _mayRequestAds = false;
        if (!completer.isCompleted) completer.complete(_mayRequestAds);
      },
    );
    return completer.future;
  }

  Future<void> _onConsentInfoUpdated() async {
    try {
      final info = ConsentInformation.instance;
      _status = await info.getConsentStatus();
      if (_status == ConsentStatus.required &&
          await info.isConsentFormAvailable()) {
        await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
          _error = formError;
        });
      }
      _mayRequestAds = await info.canRequestAds();
    } catch (_) {
      _mayRequestAds = false;
    }
  }
}