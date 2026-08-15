# StreamFlow roadmap

## 0.5.1 — Release hardening

Completed:

- authenticated TV receiver protocol v2 with 8-digit pairing
- remembered receiver credentials on mobile
- Media3 player-thread serialization
- remote polling overlap protection
- browser persistence race fixes
- bounded detected-media collections
- incremental ad-block DOM cleanup
- mDNS lifecycle hardening and IPv4/IPv6-safe addressing
- local-file HTTP/range hardening
- Android TV R8/resource shrinking and release lint
- stricter CI/toolchain/release-signing gates
- regression tests for receiver auth, URL handling, controller startup and local byte ranges

## Next: 0.6.x — Receiver reliability

- rotate/revoke trusted receiver pairing from the TV UI
- session tokens derived from initial pairing instead of sending the pairing code on every request
- WebSocket/SSE receiver events to reduce status polling
- automatic reconnect after Wi-Fi interruption
- receiver diagnostics screen with protocol/network status
- structured error codes surfaced in the mobile UI

## 0.7.x — Media pipeline

- HLS master-playlist parsing and quality selection
- subtitle discovery and SRT/VTT transfer
- playback queue
- richer media metadata and deduplication
- optional direct-URL entry screen

## 0.8.x — Additional receiver ecosystems

- Google Cast provider
- DLNA/UPnP provider
- provider capability abstraction and device compatibility matrix

## 1.0 release criteria

- all CI release gates green from one immutable release commit
- stable production Android signing keys configured
- AltStore source populated with real hosted IPA release metadata
- physical-device regression matrix completed
- long-duration HLS/DASH playback soak test completed
- large local-file range/seek soak test completed
- foreground/background and reconnect scenarios completed
- privacy/security review completed
- release diagnostics and support information documented

Out of scope:

- DRM/key extraction
- Widevine/FairPlay bypass
- paywall/access-control bypass
- bundled pirate IPTV/media sources
