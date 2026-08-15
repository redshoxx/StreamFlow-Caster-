# Changelog

## 0.5.1 - 2026-08-15

- Release hardening across Android, iOS and Android TV.
- Serialized all Media3/ExoPlayer access onto the Android TV application thread.
- Added authenticated receiver control with an 8-digit TV pairing code and persisted trusted-device credentials on mobile.
- Added pairing rate limiting, request-size limits and stricter receiver URL/seek/volume validation.
- Removed permissive receiver CORS and added no-cache / nosniff response hardening.
- Prevented overlapping remote-control status polling and protected user seek interactions from background refreshes.
- Fixed receiver stop state so the TV returns cleanly to the idle screen.
- Fixed browser-history startup races and serialized local preference writes.
- Capped session media collections to prevent unbounded memory growth.
- Reduced ad-block MutationObserver work by scanning only newly inserted DOM nodes.
- Hardened mDNS discovery lifecycle and IPv4/IPv6 receiver addressing.
- Hardened local-file HTTP streaming, interface selection, range responses and stream-error handling.
- Added HTTP byte-range integration tests and receiver/pairing regression tests.
- Enabled Android TV R8/resource shrinking and Android release lint gates.
- Added Android TV launcher icon/banner assets required for Leanback launchers.
- Pinned the CI Flutter toolchain and strengthened Android production-signing gates.

## 0.5.0 - 2026-08-15

- Added a built-in ad and tracker blocker to the Android/iOS browser.
- Ad blocking is enabled by default and the preference persists across app restarts.
- Added host-based blocking for common advertising and tracking networks.
- Added cosmetic DOM cleanup for common ad containers, ad iframes and injected ad elements.
- Added blocking hooks for popup windows, `fetch`, XHR and `sendBeacon` requests inside loaded pages.
- Added an in-browser shield control and live blocked-item counter.
- Ad/tracker URLs are excluded from the detected-media list so they are not offered as castable media.
- Added unit tests for ad-host matching.

## 0.4.0 - 2026-08-15

- Added persistent browser history and favorites on Android and iOS.
- Added a dedicated browser library with Favorite and History tabs.
- Added one-tap bookmark controls in the browser header.
- Added local history cleanup and individual entry removal.
- Uses Flutter's modern `SharedPreferencesAsync` API instead of the legacy cached API.
- Browser history is capped at 100 unique URLs and favorites at 100 entries.

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
