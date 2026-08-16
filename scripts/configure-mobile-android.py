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
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_MULTICAST_STATE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
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

MAIN_ACTIVITY = '''package com.redshoxx.streamflow

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        acquireMulticastLock()
    }

    override fun onResume() {
        super.onResume()
        acquireMulticastLock()
    }

    override fun onPause() {
        releaseMulticastLock()
        super.onPause()
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifiManager = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val lock = wifiManager.createMulticastLock("streamflow-device-discovery")
        lock.setReferenceCounted(false)
        try {
            lock.acquire()
            multicastLock = lock
        } catch (_: Throwable) {
            try {
                if (lock.isHeld) lock.release()
            } catch (_: Throwable) {
                // Discovery services still get a chance to use platform-managed mDNS.
            }
        }
    }

    private fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        multicastLock = null
        try {
            if (lock.isHeld) lock.release()
        } catch (_: Throwable) {
            // Ignore teardown races from Wi-Fi state changes.
        }
    }
}
'''


def _android_attr(name: str) -> str:
    return f"{ANDROID}{name}"


def _ensure_permission(root: ET.Element, application_index: int, name: str, **attrs: str) -> int:
    for element in root.findall("uses-permission"):
        if element.get(_android_attr("name")) == name:
            for key, value in attrs.items():
                element.set(_android_attr(key), value)
            return application_index

    attributes = {_android_attr("name"): name}
    attributes.update({_android_attr(key): value for key, value in attrs.items()})
    root.insert(application_index, ET.Element("uses-permission", attributes))
    return application_index + 1


def _ensure_application_child(
    application: ET.Element,
    tag: str,
    android_name: str,
    attributes: dict[str, str],
) -> ET.Element:
    for child in application.findall(tag):
        if child.get(_android_attr("name")) == android_name:
            for key, value in attributes.items():
                child.set(_android_attr(key), value)
            return child

    values = {_android_attr("name"): android_name}
    values.update({_android_attr(key): value for key, value in attributes.items()})
    child = ET.SubElement(application, tag, values)
    return child


def configure(path: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"AndroidManifest.xml not found: {path}")

    tree = ET.parse(path)
    root = tree.getroot()
    application = root.find("application")
    if application is None:
        raise SystemExit("Generated Android manifest has no <application> element")

    application_index = list(root).index(application)
    for permission in REQUIRED_PERMISSIONS:
        application_index = _ensure_permission(
            root,
            application_index,
            permission,
        )

    application_index = _ensure_permission(
        root,
        application_index,
        "android.permission.NEARBY_WIFI_DEVICES",
        usesPermissionFlags="neverForLocation",
    )

    application.set(_android_attr("label"), "StreamFlow")
    application.set(_android_attr("allowBackup"), "false")
    application.set(_android_attr("icon"), "@drawable/streamflow_app_icon")
    application.set(_android_attr("roundIcon"), "@drawable/streamflow_app_icon")
    # StreamFlow talks to its authenticated receiver, DLNA renderers and temporary
    # local media server over HTTP on the private LAN. Public browsing remains HTTPS-first.
    application.set(_android_attr("usesCleartextTraffic"), "true")

    _ensure_application_child(
        application,
        "meta-data",
        "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME",
        {"value": "com.felnanuke.google_cast.GoogleCastOptionsProvider"},
    )
    _ensure_application_child(
        application,
        "service",
        "com.google.android.gms.cast.framework.media.MediaNotificationService",
        {
            "exported": "false",
            "foregroundServiceType": "mediaPlayback",
        },
    )

    drawable = path.parent / "res" / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / "streamflow_app_icon.xml").write_text(APP_ICON, encoding="utf-8")

    # Android 12 and older Android 13 extension levels require an explicit
    # MulticastLock for reliable foreground mDNS reception. It also improves
    # SSDP/DLNA discovery on devices that aggressively filter multicast traffic.
    main_activity = (
        path.parent
        / "kotlin"
        / "com"
        / "redshoxx"
        / "streamflow"
        / "MainActivity.kt"
    )
    main_activity.parent.mkdir(parents=True, exist_ok=True)
    main_activity.write_text(MAIN_ACTIVITY, encoding="utf-8")

    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "apps/mobile/android/app/src/main/AndroidManifest.xml"
    )
    configure(manifest)
