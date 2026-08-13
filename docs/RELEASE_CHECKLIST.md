# Docvera PDF Editor — V1 Release Checklist

Checklist for shipping the first public build (Android + iOS). The app is
currently **free with ads**; every entitlement is granted and banner ads are
wired into the home, merge, and split screens. Web exists but is ad-free.

## 1. Signing & identity

- [ ] Android: create a release keystore, put `key.properties` at
      `android/key.properties` (it is gitignored), and uncomment/enable the
      release signing block in `android/app/build.gradle.kts`. Currently the
      release build signs with the debug key (`signingConfig = debug`) — see
      the `TODO` in that file.
- [ ] iOS: set the production bundle signing team and distribution
      certificate in Xcode (`Runner` target → Signing & Capabilities).

## 2. AdMob / Google Mobile Ads

- [ ] Create an AdMob app for each platform (Android + iOS) and grab the
      **production app IDs** and the production **banner ad unit IDs**.
- [ ] Replace the native TEST app IDs (required — the SDKs read these before
      any Dart runs):
  - Android: `android/app/src/main/AndroidManifest.xml`
    → `com.google.android.gms.ads.APPLICATION_ID`
  - iOS: `ios/Runner/Info.plist` → `GADApplicationIdentifier`
- [ ] Supply production ad unit IDs at build time (never hardcoded):
  ```sh
  flutter build apk --release --dart-define=ADMOB_USE_PRODUCTION=true \
    --dart-define=ADMOB_ANDROID_BANNER=<prod-id>

  flutter build ipa --release --dart-define=ADMOB_USE_PRODUCTION=true \
    --dart-define=ADMOB_IOS_BANNER=<prod-id>
  ```
  Without `ADMOB_USE_PRODUCTION=true` the app uses Google's test units.
  See `docs/ADS_SETUP.md`.
- [ ] In the AdMob console, set the **Privacy policy URL** to the hosted web
      build legal route (see `docs/ADS_SETUP.md` → "Privacy policy URL").
- [ ] Confirm the UMP consent form is live for both stores (it loads from the
      AdMob console, not the app binary).

## 3. Store listings

- [ ] **Privacy policy URL** (required by both stores and AdMob):
      `https://<host>/#/privacy` (served by the web build).
- [ ] Terms of service URL (Google Play): `https://<host>/#/terms`.
- [ ] App title: **Docvera PDF Editor**.
- [ ] Screenshots / store assets from real renderings of the app.
- [ ] Icon/launcher: current launcher is the Flutter default — replace with
      the Docvera mark (Android mipmaps + iOS AppIcon + web `icons/` +
      `web/favicon.png`).

## 4. Version & build

- [ ] Confirm `version:` in `pubspec.yaml` is the planned public version
      (currently `1.0.0+1`). `+N` is the build number — bump on each distro.
- [ ] iOS deployment target is 13.0 (fine for current Flutter 3.44).
- [ ] Verify release builds:
  ```sh
  flutter analyze
  flutter test
  flutter build apk --release
  flutter build appbundle --release        # Play
  flutter build ipa --release              # App Store Connect
  flutter build web --release              # for the hosted legal routes
  ```

## 5. Privacy / data profile

- [ ] No network calls except the ad SDK on mobile; documents stay on device
      (path_provider + shared_preferences). Confirm nothing new was added.
- [ ] The web build hosts `/privacy` and `/terms`; keep the copy in
      `lib/src/legal/legal_pages.dart` in sync with any store-paste version.
- [ ] If you later ship a paid tier or rewarded ads, update
      `lib/src/ads/monetization.dart` (the `EntitlementManager` seam) and this
      checklist before release.

## 6. Pre-submission QA

- [ ] `flutter analyze` clean.
- [ ] Full `flutter test` suite green (28 test files).
- [ ] Manual smoke: open/edit/annotate/save a real-world PDF; merge; split;
      banner shows only after UMP consent; slot collapses on failure; web
      shows no ads and no SDK errors in the browser console.
- [ ] Test the release build (not just debug): ads load against the validate
      test units by default; verify consent flow appears on a fresh install.