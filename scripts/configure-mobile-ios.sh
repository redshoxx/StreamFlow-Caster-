#!/usr/bin/env bash
set -euo pipefail

IOS_DIR="${1:-apps/mobile/ios}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST="$IOS_DIR/Runner/Info.plist"
PBXPROJ="$IOS_DIR/Runner.xcodeproj/project.pbxproj"
PODFILE="$IOS_DIR/Podfile"
ICON_SOURCE="$ROOT_DIR/assets/streamflow-icon.png"
ICONSET="$IOS_DIR/Runner/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$PLIST" ]]; then
  echo "Info.plist not found: $PLIST" >&2
  exit 1
fi
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "App icon not found: $ICON_SOURCE" >&2
  exit 1
fi

set_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
}

set_string CFBundleDisplayName StreamFlow
set_string CFBundleName StreamFlow
set_string NSLocalNetworkUsageDescription "StreamFlow discovers StreamFlow TV, Chromecast and compatible receivers on your local network."

# Google Cast on iOS requires the generic Google Cast Bonjour service plus the
# receiver-specific service. CC1AD845 is Google's Default Media Receiver ID.
/usr/libexec/PlistBuddy -c "Delete :NSBonjourServices" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices:0 string _streamflow._tcp" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices:1 string _googlecast._tcp" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices:2 string _CC1AD845._googlecast._tcp" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :NSAppTransportSecurity:NSAllowsLocalNetworking" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"

# The current Google Cast iOS Sender SDK supports iOS 15 and later.
if [[ -f "$PBXPROJ" ]]; then
  /usr/bin/sed -E -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' "$PBXPROJ"
fi
if [[ -f "$PODFILE" ]]; then
  python3 - "$PODFILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(r"^\s*#?\s*platform\s+:ios,\s*['\"][^'\"]+['\"]\s*$", re.MULTILINE)
replacement = "platform :ios, '15.0'"
if pattern.search(text):
    text = pattern.sub(replacement, text, count=1)
else:
    text = replacement + "\n\n" + text
path.write_text(text, encoding="utf-8")
PY
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "sips is required to generate iOS launcher icons." >&2
  exit 1
fi

shopt -s nullglob
icons=("$ICONSET"/*.png)
if (( ${#icons[@]} == 0 )); then
  echo "No generated iOS app icons found in $ICONSET" >&2
  exit 1
fi
for icon in "${icons[@]}"; do
  width="$(sips -g pixelWidth "$icon" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$icon" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  if [[ -z "$width" || -z "$height" ]]; then
    echo "Could not determine icon dimensions: $icon" >&2
    exit 1
  fi
  sips -z "$height" "$width" "$ICON_SOURCE" --out "$icon" >/dev/null
done
