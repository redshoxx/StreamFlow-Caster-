#!/usr/bin/env python3
"""Apply deterministic release settings to a generated Flutter Android app."""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID = f"{{{ANDROID_NS}}}"
ET.register_namespace("android", ANDROID_NS)

REQUIRED_PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.CHANGE_WIFI_MULTICAST_STATE",
)

APP_ICON = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#090B10" android:pathData="M0,0h108v108h-108z" />
    <path android:fillColor="#171B26" android:pathData="M16,16h76a16,16 0,0 1,16 16v44a16,16 0,0 1,-16 16h-76z" />
    <path android:fillColor="#5B7CFA" android:pathData="M16,16h12v76h-12z" />
    <path android:fillColor="#FFFFFF" android:pathData="M42,34h36a8,8 0,0 1,8 8v24a8,8 0,0 1,-8 8h-36z" />
    <path android:fillColor="#5B7CFA" android:pathData="M55,44v20l18,-10z" />
    <path android:fillColor="#FFFFFF" android:pathData="M34,69a3,3 0,1 1,0,6a3,3 0,1 1,0,-6" />
</vector>
'''


def configure(path: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"AndroidManifest.xml not found: {path}")

    tree = ET.parse(path)
    root = tree.getroot()
    application = root.find("application")
    if application is None:
        raise SystemExit("Generated Android manifest has no <application> element")

    existing_permissions = {
        element.get(f"{ANDROID}name")
        for element in root.findall("uses-permission")
    }
    application_index = list(root).index(application)

    for permission in REQUIRED_PERMISSIONS:
        if permission in existing_permissions:
            continue
        element = ET.Element(
            "uses-permission",
            {f"{ANDROID}name": permission},
        )
        root.insert(application_index, element)
        application_index += 1

    application.set(f"{ANDROID}label", "StreamFlow")
    application.set(f"{ANDROID}allowBackup", "false")
    application.set(f"{ANDROID}icon", "@drawable/streamflow_app_icon")
    application.set(f"{ANDROID}roundIcon", "@drawable/streamflow_app_icon")
    # StreamFlow talks to its authenticated receiver and temporary media server
    # over HTTP on the private LAN. Public web browsing remains HTTPS-first.
    application.set(f"{ANDROID}usesCleartextTraffic", "true")

    drawable = path.parent / "res" / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / "streamflow_app_icon.xml").write_text(APP_ICON, encoding="utf-8")

    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "apps/mobile/android/app/src/main/AndroidManifest.xml"
    )
    configure(manifest)
