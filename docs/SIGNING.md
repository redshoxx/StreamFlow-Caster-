# Android production signing

StreamFlow uses separate stable signing keys for the Android smartphone app and the Android TV receiver. Keep both original keystores permanently and never commit keystores or passwords to Git.

A tagged GitHub release is intentionally blocked until both Android applications can be production-signed. Branch builds remain available for testing.

## Mobile app secrets

Configure under **Settings → Secrets and variables → Actions**:

- `ANDROID_MOBILE_KEYSTORE_BASE64`
- `ANDROID_MOBILE_KEYSTORE_PASSWORD`
- `ANDROID_MOBILE_KEY_ALIAS`
- `ANDROID_MOBILE_KEY_PASSWORD`

Example keystore creation:

```bash
keytool -genkeypair \
  -v \
  -keystore streamflow-mobile-release.jks \
  -alias streamflow-mobile \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

## Android TV secrets

Configure:

- `ANDROID_TV_KEYSTORE_BASE64`
- `ANDROID_TV_KEYSTORE_PASSWORD`
- `ANDROID_TV_KEY_ALIAS`
- `ANDROID_TV_KEY_PASSWORD`

Example:

```bash
keytool -genkeypair \
  -v \
  -keystore streamflow-tv-release.jks \
  -alias streamflow-tv \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

## Encode a keystore

macOS / Linux:

```bash
base64 < streamflow-mobile-release.jks | tr -d '\n'
```

PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("streamflow-mobile-release.jks"))
```

Use the resulting Base64 value for the corresponding `*_KEYSTORE_BASE64` secret.

## CI behavior

Branch workflows always build installable test artifacts. When the matching four secrets exist, they additionally produce and verify the production-signed APK.

The tag workflow is stricter: it exits with an error if either production signing configuration is missing. A public GitHub release therefore cannot accidentally publish an Android APK with a temporary or unstable signing identity.

## Key continuity

An installed Android application can normally be updated only by an APK signed by the same accepted signing identity. Back up each release keystore and its passwords in an offline secure location before publishing the first production version.
