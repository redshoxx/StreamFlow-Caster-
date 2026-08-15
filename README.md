# StreamFlow Caster

StreamFlow is a clean-room cross-platform web-media caster for Android, iPhone/iPad and Android TV / Google TV.

The project is designed to browse normal websites, detect directly playable media, select local media files and send supported URLs/files to a StreamFlow TV receiver on the same local network.

> StreamFlow does not implement DRM extraction, Widevine/FairPlay bypass, paywall bypass or access-control circumvention. Use it only with media you are authorized to access.

## Current release-candidate scope — 0.5.1

### Android / iOS mobile app

- Material 3 browser UI
- WebView-based browsing
- direct video/audio URL detection
- HLS (`.m3u8`) and DASH (`.mpd`) detection
- DOM media scanning
- built-in ad/tracker blocker, enabled by default
- persistent browser favorites and history
- media library with type filters
- mDNS/Zeroconf discovery for StreamFlow TV
- one-time 8-digit TV pairing code, remembered per receiver
- cast session state and Now Playing mini-player
- play, pause, stop, seek, ±10 s and volume controls
- local video/audio file selection
- temporary tokenized LAN file server with HTTP byte-range support
- system light/dark theme

### Android TV / Google TV receiver

- native Android TV application
- Media3 / ExoPlayer playback
- HLS and DASH playback through Media3
- `_streamflow._tcp` mDNS advertisement
- authenticated local receiver API
- persistent 8-digit pairing code displayed on the idle screen
- play, pause, stop, seek, volume and status endpoints
- optimized release build with R8/resource shrinking
- Android TV launcher icon/banner

## Pairing and receiver protocol

StreamFlow TV advertises protocol version 2.

Public discovery endpoint:

```http
GET /api/v1/health
```

All control/status endpoints require the pairing header:

```http
X-StreamFlow-Pairing-Code: 12345678
```

Supported authenticated endpoints:

```text
GET  /api/v1/status
POST /api/v1/load
POST /api/v1/play
POST /api/v1/pause
POST /api/v1/stop
POST /api/v1/seek
POST /api/v1/volume
```

The receiver restricts media loading to HTTP/HTTPS URLs, limits request sizes and rate-limits repeated invalid pairing attempts.

## Repository layout

```text
apps/
  mobile/       Flutter Android/iOS controller
  android-tv/   Native Kotlin/Compose TV receiver

docs/
  ARCHITECTURE.md
  ROADMAP.md
  SIGNING.md
.github/workflows/
  flutter-checks.yml
  android-mobile.yml
  android-tv.yml
  ios-check.yml
  release.yml
```

## Local mobile development

The native Android/iOS host projects are generated reproducibly by Flutter.

```bash
cd apps/mobile
flutter create --platforms=android,ios --org com.redshoxx --project-name streamflow .
flutter pub get
flutter analyze
flutter test
```

Android test/release build:

```bash
flutter build apk --release
```

iOS compile validation:

```bash
flutter build ios --release --no-codesign
```

## Android TV development

Requirements: JDK 17 and Gradle 9.5 compatible tooling.

```bash
cd apps/android-tv
gradle :app:lintRelease :app:assembleDebug :app:assembleRelease
```

## CI release gates

Every relevant mobile change runs:

- dependency resolution
- `flutter analyze`
- `flutter test`
- Android release APK compilation
- unsigned iOS release/AltStore IPA compilation

Every Android TV change runs:

- Android release lint
- debug APK build
- R8/resource-shrunk release APK build

Tagged public releases additionally require stable production signing keys for both Android phone and Android TV builds. See `docs/SIGNING.md`.

## Release status

CI passing is necessary but not a substitute for physical-device validation. Before a public production release, validate at minimum:

- Android phone on real Wi-Fi
- iPhone with the iOS Local Network permission prompt
- Android TV / Google TV pairing and discovery
- HLS/DASH playback over a long session
- large local-file seeking
- app foreground/background transitions
- router/VPN/multiple-interface edge cases
- install → update using the same production signing identity

## License

Apache-2.0. See `LICENSE`.
