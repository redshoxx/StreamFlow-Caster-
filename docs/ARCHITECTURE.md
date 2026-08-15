# Architecture

## Mobile

The mobile app owns browsing, media discovery, local file serving, receiver discovery, and remote playback control.

Core boundaries:

- `media/`: extracts and classifies playable sources.
- `cast/`: discovers receivers and sends protocol commands.
- `server/`: exposes user-selected local files to LAN receivers with HTTP Range support.
- `screens/`: presentation layer.

## Android TV

The TV app is a receiver:

1. `NsdAdvertiser` publishes `_streamflow._tcp`.
2. `ReceiverHttpServer` accepts local playback commands.
3. `ReceiverController` owns the Media3 ExoPlayer and playback state.
4. `MainActivity` renders receiver/playback state using Compose.

## Protocol evolution

V0.1 uses JSON over HTTP on the local network. V1.0 should add:

- pairing code
- per-device secret
- signed/session-authenticated requests
- WebSocket state events
- protocol version negotiation
- subtitle/audio track descriptors
- queue synchronization
