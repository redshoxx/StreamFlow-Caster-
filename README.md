# StreamFlow Caster

Clean-room cross-platform web media caster inspired by the workflow of Web Video Cast, with an original codebase and UI.

## Targets

- Android phone/tablet (Flutter)
- iPhone/iPad (Flutter, AltStore-compatible build path)
- Android TV / Google TV receiver (Kotlin + Jetpack Compose + Media3)

## Implemented in this initial foundation

- Browser shell with WebView
- DOM-based HTML5 media discovery (`video`, `audio`, `source`)
- Media URL classification (MP4, WebM, HLS/M3U8, DASH/MPD, audio)
- Android TV receiver discovery over mDNS/NSD (`_streamflow._tcp`)
- Mobile receiver HTTP client (load/play/pause/seek/stop/status)
- Local HTTP media server with byte-range support
- Android TV receiver HTTP API
- Android TV NSD advertisement
- Media3 playback on Android TV
- GitHub Actions for Flutter checks, Android mobile APK, Android TV APK and release artifacts
- AltStore source template

## Important scope

StreamFlow does not bypass DRM, authentication, paywalls, access controls, Widevine, FairPlay, PlayReady, or encrypted media authorization. It only handles media the user is authorized to access and that can legally/technically be played or cast.

## Repository layout

```text
apps/
  mobile/       Flutter controller/browser app
  android-tv/   Native Android TV receiver
.github/workflows/
docs/
scripts/
```

## Mobile prerequisites

The repository intentionally keeps generated Flutter platform scaffolding reproducible instead of committing machine-generated boilerplate.

```bash
cd apps/mobile
flutter create --platforms=android,ios --org com.redshoxx --project-name streamflow .
flutter pub get
flutter run
```

The `flutter create` command preserves `lib/`, `test/`, and `pubspec.yaml` while generating native Android/iOS host projects.

### Android release APK

```bash
cd apps/mobile
flutter create --platforms=android --org com.redshoxx --project-name streamflow .
flutter pub get
flutter build apk --release
```

### iOS / AltStore IPA

On macOS with Xcode:

```bash
cd apps/mobile
flutter create --platforms=ios --org com.redshoxx --project-name streamflow .
flutter pub get
flutter build ios --release --no-codesign
```

Open `ios/Runner.xcworkspace`, choose your Apple Development team/bundle ID, archive, then export an IPA suitable for sideloading. AltStore signing/refresh rules still apply.

## Android TV

Requirements: JDK 17, Android SDK 37, Gradle 9.5+.

```bash
cd apps/android-tv
gradle :app:assembleDebug
```

Release:

```bash
gradle :app:assembleRelease
```

## Receiver protocol

The TV advertises:

```text
_streamflow._tcp
```

HTTP API:

```text
GET  /api/v1/status
POST /api/v1/load
POST /api/v1/play
POST /api/v1/pause
POST /api/v1/stop
POST /api/v1/seek
```

`POST /api/v1/load` body:

```json
{
  "url": "https://example.com/video.m3u8",
  "title": "Example"
}
```

`POST /api/v1/seek` body:

```json
{ "positionMs": 42000 }
```

## Security roadmap

The first receiver foundation is LAN-only and intentionally small. Before a public release, complete pairing, per-device session tokens, request authentication, rate limiting, secure storage, and origin validation listed in `docs/ROADMAP.md`.

## License

Apache-2.0. This repository contains original code only; no Web Video Cast source code, branding, icons, or proprietary assets are included.
