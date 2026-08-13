# Docvera PDF Editor — AdMob Setup

Central configuration for the Google Mobile Ads (AdMob) integration.

## How it works

- The **app-level AdMob application IDs** are declared natively because the
  SDKs read them before any Flutter/Dart runs:

  | Platform | File | Key |
  |---|---|---|
  | Android | `android/app/src/main/AndroidManifest.xml` | `com.google.android.gms.ads.APPLICATION_ID` |
  | iOS | `ios/Runner/Info.plist` | `GADApplicationIdentifier` |

  Both currently hold **Google's TEST values** (identified inline). They must
  be replaced with your production app IDs from the AdMob console before
  release.

- The **ad unit IDs** live in `lib/src/ads/ad_config.dart`. Test units are the
  Google-published ones and are used by default. Production units are supplied
  at build time via `--dart-define` and are **never hardcoded**.

## Building with production ads

```sh
# Android (APK or appbundle)
flutter build apk --release \
  --dart-define=ADMOB_USE_PRODUCTION=true \
  --dart-define=ADMOB_ANDROID_BANNER=ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy

# iOS
flutter build ipa --release \
  --dart-define=ADMOB_USE_PRODUCTION=true \
  --dart-define=ADMOB_IOS_BANNER=ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy
```

If you later wire rewarded ads (`RewardedAdManager` in
`lib/src/ads/rewarded_ad_manager.dart` — infrastructure exists but no flow
consumes a reward yet), add:
`--dart-define=ADMOB_ANDROID_REWARDED=... --dart-define=ADMOB_IOS_REWARDED=...`

> If you use a release-key `build.gradle.kts` signing config and want ad units
> stored in that file, you could move the IDs there instead; the current design
> (dart-defines) keeps them out of source control entirely.

## Consent (UMP)

`lib/src/ads/consent_manager.dart` runs Google's User Messaging Platform flow:

- In **debug builds** consent is auto-granted so development never stalls.
- In **release** the consent form (configured in the AdMob console, not the
  app) is shown when required; ads are gated until the user consents.
- Consent failures never block startup — banner slots simply stay collapsed
  (`AdBannerView` renders zero height).

## Privacy policy URL (AdMob policy requirement)

AdMob and both stores require a reachable privacy policy. The web build serves
one at a dedicated route:

```
https://<host>/#/privacy
https://<host>/#/terms
```

`<host>` is wherever the Flutter web release is hosted (GitHub Pages, a static
host, etc.). Build it with:

```sh
flutter build web --release
```

The content lives in `lib/src/legal/legal_pages.dart`. If you change the text,
rebuild & redeploy so the live URL stays in sync with what reviewers see.

## Platform notes

- Ads are mobile-only; the web build never loads the ad SDK
  (`AdConfig.isSupportedOnPlatform`).
- iOS: `Info.plist` already includes the SKAdNetwork identifiers AdMob ships.
- Android: `INTERNET` + `ACCESS_NETWORK_STATE` permissions are declared in the
  main manifest.
- If a slot fails (no consent, offline, no fill) the UI is unaffected: the
  banner collapses and never pushes content around (`AdBannerView`).