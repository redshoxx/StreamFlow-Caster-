# Android TV release signing

StreamFlow's Android TV release APK must be signed with one stable private key so later versions can update the installed app.

Do not commit the keystore or passwords to the repository.

## Required GitHub Actions secrets

Create these repository secrets under **Settings → Secrets and variables → Actions**:

- `ANDROID_TV_KEYSTORE_BASE64` — Base64 encoded JKS/keystore file
- `ANDROID_TV_KEYSTORE_PASSWORD` — keystore password
- `ANDROID_TV_KEY_ALIAS` — signing key alias
- `ANDROID_TV_KEY_PASSWORD` — key password

## Generate a release keystore

Run this once on a trusted computer and keep the resulting file backed up securely:

```bash
keytool -genkeypair \
  -v \
  -keystore streamflow-tv-release.jks \
  -alias streamflow-tv \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Encode it for the GitHub secret:

### macOS / Linux

```bash
base64 < streamflow-tv-release.jks | tr -d '\n'
```

### PowerShell

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("streamflow-tv-release.jks"))
```

Store the Base64 output as `ANDROID_TV_KEYSTORE_BASE64`.

## CI behavior

The branch workflow builds:

- `StreamFlow-TV-test.apk` — installable debug-signed test build
- `StreamFlow-TV-release-unsigned.apk` — optimized but not installable as the final production release
- `StreamFlow-TV-release.apk` — produced only when all four signing secrets exist

The tag release workflow intentionally fails the Android TV release job when signing secrets are missing. This prevents publishing an unsigned or unstable-signature production APK.

## Important

Keep the original keystore permanently. If it is lost, a future APK signed with a different key cannot update an existing installation with the same application ID.
