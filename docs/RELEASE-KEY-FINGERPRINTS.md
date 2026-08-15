# StreamFlow Android release key fingerprints

These are the public SHA-256 certificate fingerprints for the first production signing identities generated for StreamFlow on 2026-08-15.

## Android mobile

- Alias: `streamflow-mobile`
- SHA-256: `3A:E6:2F:E5:EF:18:73:CA:41:12:93:E9:5D:CC:AA:99:66:39:2D:AC:A5:DA:5B:A6:E2:8E:64:82:3C:98:D3:C8`

## Android TV

- Alias: `streamflow-tv`
- SHA-256: `EC:3B:C7:E0:78:DA:43:49:6C:5D:83:4B:DB:49:F5:2D:69:A4:A4:F9:B7:E1:0A:20:98:E2:DE:ED:1E:3D:36:0A`

## Release policy

Future Android production APKs must verify against the corresponding fingerprint above. The private keystores and passwords must never be committed to this repository. Keep at least two offline backups of the original signing package before publishing the first production release.
