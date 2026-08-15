#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/apps/mobile"
flutter create --platforms=android,ios --org com.redshoxx --project-name streamflow .
python3 "$ROOT/scripts/configure-mobile-android.py" android/app/src/main/AndroidManifest.xml
flutter pub get
flutter analyze
flutter test
