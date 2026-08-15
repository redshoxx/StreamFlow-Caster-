#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/mobile"
flutter create --platforms=android,ios --org com.redshoxx --project-name streamflow .
flutter pub get
flutter analyze
flutter test
