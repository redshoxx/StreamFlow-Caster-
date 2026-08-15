#!/usr/bin/env python3
"""Apply deterministic release networking settings to a generated Flutter Android manifest."""

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
    # StreamFlow talks to its authenticated receiver and temporary media server
    # over HTTP on the private LAN. Public web browsing remains HTTPS-first.
    application.set(f"{ANDROID}usesCleartextTraffic", "true")

    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "apps/mobile/android/app/src/main/AndroidManifest.xml"
    )
    configure(manifest)
