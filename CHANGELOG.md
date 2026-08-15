# Changelog

## 0.3.0 - 2026-08-15

- Added real local-file casting from Android and iOS to the StreamFlow Android TV receiver.
- Added a temporary tokenized local HTTP media endpoint bound to the phone's LAN address.
- Added GET/HEAD and byte-range support (`206 Partial Content`) for seeking large local files.
- Added video and audio file selection with size/status UI.
- Cast-session cleanup now shuts down temporary local streaming resources automatically.
- Uses Flutter's first-party `file_selector` plugin for native Android/iOS file selection and AGP 9 compatibility.

## 0.2.0 - 2026-08-15

- Rebuilt the mobile browser UI with modern address and playback controls.
- Added session-wide detected media library with filters and URL actions.
- Added preferred-device selection and improved receiver discovery UI.
- Added persistent in-app casting session state and compact now-playing bar.
- Added full cast remote with status polling, play/pause, seek, stop and volume.
- Added receiver volume endpoint and state reporting on Android TV.
- Improved DOM/resource media scanning for direct video, HLS, DASH and audio URLs.

## 0.1.0 - 2026-08-15

- Initial StreamFlow mobile and Android TV foundation.
- Browser media detection, mDNS receiver discovery, receiver HTTP API and local media server.
- Android, Android TV and AltStore-compatible iOS build pipelines.
