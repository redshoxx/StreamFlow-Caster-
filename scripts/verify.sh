#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v flutter >/dev/null 2>&1; then
  (cd "$ROOT/apps/mobile" && flutter pub get && flutter analyze && flutter test)
else
  echo "Flutter not installed; mobile validation skipped." >&2
fi

if command -v gradle >/dev/null 2>&1; then
  (cd "$ROOT/apps/android-tv" && gradle :app:assembleDebug)
else
  echo "Gradle not installed; Android TV validation skipped." >&2
fi
