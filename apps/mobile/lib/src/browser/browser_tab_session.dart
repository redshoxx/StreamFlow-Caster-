import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/streamflow_controller.dart';
import '../media/media_detector.dart';
import '../models/detected_media.dart';
import 'ad_blocker.dart';

class BrowserTabSession {
  BrowserTabSession({
    required this.id,
    required this.initialUri,
    required this.appController,
    required this.adBlocker,
    required this.onChanged,
  }) {
    address = TextEditingController(text: initialUri.toString());
    currentUri = initialUri;

    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'StreamFlowAdBlock',
        onMessageReceived: _onAdBlockMessage,
      )
      ..addJavaScriptChannel(
        'StreamFlowMedia',
        onMessageReceived: _onMediaMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            progress = value;
            _notify();
          },
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onUrlChange: (change) {
            final value = change.url;
            if (value == null) return;
            final uri = Uri.tryParse(value);
            if (uri == null) return;
            currentUri = uri;
            if (!addressHasFocus) address.text = value;
            _notify();
          },
          onNavigationRequest: (request) {
            if (adBlockEnabled && adBlocker.shouldBlockUrl(request.url)) {
              blockedAds += 1;
              _notify();
              return NavigationDecision.prevent;
            }
            _capture(request.url);
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  static const homeUrl = 'https://www.google.com';
  static const _maxPageMedia = 120;

  final int id;
  final Uri initialUri;
  final StreamFlowController appController;
  final AdBlocker adBlocker;
  final VoidCallback onChanged;

  late final WebViewController web;
  late final TextEditingController address;
  final FocusNode addressFocus = FocusNode();
  final List<DetectedMedia> pageMedia = <DetectedMedia>[];
  final List<Timer> _injectionTimers = <Timer>[];

  bool adBlockEnabled = true;
  bool initialized = false;
  bool disposed = false;
  int progress = 0;
  int blockedAds = 0;
  int _pageGeneration = 0;
  String pageTitle = 'Neuer Tab';
  Uri? currentUri;
  Timer? _lateScanTimer;

  bool get secure => currentUri?.scheme == 'https';
  bool get addressHasFocus => addressFocus.hasFocus;

  Future<void> initialize({required bool enableAdBlock}) async {
    if (disposed || initialized) return;
    initialized = true;
    adBlockEnabled = enableAdBlock;
    await web.loadRequest(initialUri);
  }

  Future<void> setAdBlockEnabled(bool enabled) async {
    if (disposed || adBlockEnabled == enabled) return;
    adBlockEnabled = enabled;
    blockedAds = 0;
    _notify();
    if (enabled) {
      await _injectHooks();
    } else {
      await web.reload();
    }
  }

  void _onAdBlockMessage(JavaScriptMessage message) {
    if (disposed || !adBlockEnabled) return;
    final delta = int.tryParse(message.message) ?? 0;
    if (delta <= 0) return;
    blockedAds += delta;
    _notify();
  }

  void _onMediaMessage(JavaScriptMessage message) {
    if (disposed) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      _capture(
        decoded['url']?.toString() ?? '',
        label: decoded['label']?.toString(),
        mime: decoded['type']?.toString(),
      );
    } catch (_) {}
  }

  void _onPageStarted(String url) {
    if (disposed) return;
    _cancelInjectionTimers();
    _lateScanTimer?.cancel();
    final generation = ++_pageGeneration;
    final uri = Uri.tryParse(url);

    currentUri = uri;
    if (!addressHasFocus) address.text = url;
    progress = 0;
    blockedAds = 0;
    pageMedia.clear();
    pageTitle = uri?.host.isNotEmpty == true ? uri!.host : 'Browser';
    _notify();

    unawaited(_injectHooks());
    for (final delay in const [40, 160, 500]) {
      _injectionTimers.add(
        Timer(Duration(milliseconds: delay), () {
          if (!disposed && generation == _pageGeneration) {
            unawaited(_injectHooks());
          }
        }),
      );
    }
  }

  Future<void> _onPageFinished(String url) async {
    if (disposed) return;
    final generation = _pageGeneration;
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    currentUri = uri;
    if (!addressHasFocus) address.text = url;
    progress = 100;
    _notify();

    await _injectHooks();
    if (disposed || generation != _pageGeneration) return;

    try {
      final title = await web.getTitle();
      if (disposed || generation != _pageGeneration) return;
      final resolved = title?.trim().isNotEmpty == true
          ? title!.trim()
          : uri.host.isNotEmpty
              ? uri.host
              : 'Browser';
      pageTitle = resolved;
      _notify();
      unawaited(appController.recordVisit(uri, resolved));
    } catch (_) {}

    await scan(expectedGeneration: generation);
    if (disposed || generation != _pageGeneration) return;
    _lateScanTimer = Timer(const Duration(seconds: 2), () {
      if (!disposed && generation == _pageGeneration) {
        unawaited(scan(expectedGeneration: generation));
        unawaited(_injectHooks());
      }
    });
  }

  Future<void> _injectHooks() async {
    if (disposed) return;
    if (adBlockEnabled) {
      try {
        await web.runJavaScript(adBlocker.javaScript);
      } catch (_) {}
    }
    try {
      await web.runJavaScript(MediaDetector.hookScript);
    } catch (_) {}
  }

  Future<void> scan({int? expectedGeneration}) async {
    if (disposed) return;
    if (expectedGeneration != null && expectedGeneration != _pageGeneration) {
      return;
    }
    try {
      final raw = await web.runJavaScriptReturningResult(
        MediaDetector.domScannerScript,
      );
      if (disposed ||
          (expectedGeneration != null &&
              expectedGeneration != _pageGeneration)) {
        return;
      }

      String json = raw.toString();
      if (json.startsWith('"') && json.endsWith('"')) {
        json = jsonDecode(json) as String;
      }
      final decoded = jsonDecode(json);
      if (decoded is! List) return;
      for (final item in decoded.whereType<Map>()) {
        _capture(
          item['url']?.toString() ?? '',
          label: item['label']?.toString(),
          mime: item['type']?.toString(),
        );
      }
    } catch (_) {}
  }

  void _capture(String url, {String? label, String? mime}) {
    if (disposed || url.isEmpty) return;
    if (adBlockEnabled && adBlocker.shouldBlockUrl(url)) return;
    final media = MediaDetector.fromUrl(url, label: label, mime: mime);
    if (media == null || pageMedia.contains(media)) return;
    pageMedia.add(media);
    if (pageMedia.length > _maxPageMedia) pageMedia.removeAt(0);
    appController.addDetectedMedia(media);
    _notify();
  }

  Future<void> goFromAddress() async {
    final raw = address.text.trim();
    if (raw.isEmpty) return;
    await web.loadRequest(normalizeAddress(raw));
  }

  Future<void> openUri(Uri uri) => web.loadRequest(uri);

  Future<void> goBack() async {
    if (await web.canGoBack()) await web.goBack();
  }

  Future<void> goForward() async {
    if (await web.canGoForward()) await web.goForward();
  }

  Future<void> home() => web.loadRequest(Uri.parse(homeUrl));

  Future<void> reload() => web.reload();

  static Uri normalizeAddress(String raw) {
    var value = raw.trim();
    if (!value.contains('://')) {
      if ((value.contains('.') || value.startsWith('localhost')) &&
          !value.contains(' ')) {
        value = 'https://$value';
      } else {
        return Uri.parse(
          'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed;
    }
    return Uri.parse(
      'https://www.google.com/search?q=${Uri.encodeQueryComponent(raw)}',
    );
  }

  void _notify() {
    if (!disposed) onChanged();
  }

  void _cancelInjectionTimers() {
    for (final timer in _injectionTimers) {
      timer.cancel();
    }
    _injectionTimers.clear();
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    _cancelInjectionTimers();
    _lateScanTimer?.cancel();
    address.dispose();
    addressFocus.dispose();
  }
}
