import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/browser_entry.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import '../storage/browser_library_store.dart';

class StreamFlowController extends ChangeNotifier {
  StreamFlowController({BrowserLibraryStore? browserLibraryStore})
      : _browserLibraryStore = browserLibraryStore ?? BrowserLibraryStore() {
    unawaited(_loadBrowserLibrary());
  }

  static const _maxHistoryEntries = 100;
  static const _maxFavoriteEntries = 100;

  final BrowserLibraryStore _browserLibraryStore;
  final List<DetectedMedia> _detectedMedia = <DetectedMedia>[];
  final List<BrowserEntry> _history = <BrowserEntry>[];
  final List<BrowserEntry> _favorites = <BrowserEntry>[];
  VoidCallback? _castCleanup;
  bool _browserLibraryLoaded = false;

  List<DetectedMedia> get detectedMedia => List.unmodifiable(_detectedMedia);
  List<BrowserEntry> get history => List.unmodifiable(_history);
  List<BrowserEntry> get favorites => List.unmodifiable(_favorites);
  bool get browserLibraryLoaded => _browserLibraryLoaded;

  CastDevice? _preferredDevice;
  CastDevice? get preferredDevice => _preferredDevice;

  CastDevice? _activeDevice;
  CastDevice? get activeDevice => _activeDevice;

  DetectedMedia? _activeMedia;
  DetectedMedia? get activeMedia => _activeMedia;

  bool get isCasting => _activeDevice != null && _activeMedia != null;

  Future<void> _loadBrowserLibrary() async {
    try {
      final snapshot = await _browserLibraryStore.load();
      _history
        ..clear()
        ..addAll(snapshot.history.take(_maxHistoryEntries));
      _favorites
        ..clear()
        ..addAll(snapshot.favorites.take(_maxFavoriteEntries));
    } finally {
      _browserLibraryLoaded = true;
      notifyListeners();
    }
  }

  void addDetectedMedia(DetectedMedia media) {
    if (_detectedMedia.contains(media)) return;
    _detectedMedia.insert(0, media);
    notifyListeners();
  }

  void clearDetectedMedia() {
    if (_detectedMedia.isEmpty) return;
    _detectedMedia.clear();
    notifyListeners();
  }

  void removeDetectedMedia(DetectedMedia media) {
    if (_detectedMedia.remove(media)) notifyListeners();
  }

  Future<void> recordVisit(Uri url, String title) async {
    if (!_supportedBrowserUri(url)) return;

    _history.removeWhere((entry) => _sameUrl(entry.url, url));
    _history.insert(
      0,
      BrowserEntry(url: url, title: title, timestamp: DateTime.now()),
    );
    if (_history.length > _maxHistoryEntries) {
      _history.removeRange(_maxHistoryEntries, _history.length);
    }
    notifyListeners();
    await _browserLibraryStore.saveHistory(_history);
  }

  bool isFavorite(Uri? url) {
    if (url == null) return false;
    return _favorites.any((entry) => _sameUrl(entry.url, url));
  }

  Future<void> toggleFavorite(Uri url, String title) async {
    if (!_supportedBrowserUri(url)) return;

    final index = _favorites.indexWhere((entry) => _sameUrl(entry.url, url));
    if (index >= 0) {
      _favorites.removeAt(index);
    } else {
      _favorites.insert(
        0,
        BrowserEntry(url: url, title: title, timestamp: DateTime.now()),
      );
      if (_favorites.length > _maxFavoriteEntries) {
        _favorites.removeRange(_maxFavoriteEntries, _favorites.length);
      }
    }
    notifyListeners();
    await _browserLibraryStore.saveFavorites(_favorites);
  }

  Future<void> removeFavorite(Uri url) async {
    final changed = _favorites.removeWhere((entry) => _sameUrl(entry.url, url)) > 0;
    if (!changed) return;
    notifyListeners();
    await _browserLibraryStore.saveFavorites(_favorites);
  }

  Future<void> removeHistoryEntry(Uri url) async {
    final changed = _history.removeWhere((entry) => _sameUrl(entry.url, url)) > 0;
    if (!changed) return;
    notifyListeners();
    await _browserLibraryStore.saveHistory(_history);
  }

  Future<void> clearHistory() async {
    if (_history.isEmpty) return;
    _history.clear();
    notifyListeners();
    await _browserLibraryStore.saveHistory(_history);
  }

  void setPreferredDevice(CastDevice device) {
    _preferredDevice = device;
    notifyListeners();
  }

  void startCasting(
    CastDevice device,
    DetectedMedia media, {
    VoidCallback? onEnd,
  }) {
    _castCleanup?.call();
    _castCleanup = onEnd;
    _preferredDevice = device;
    _activeDevice = device;
    _activeMedia = media;
    notifyListeners();
  }

  void endCasting() {
    if (!isCasting && _castCleanup == null) return;
    _castCleanup?.call();
    _castCleanup = null;
    _activeDevice = null;
    _activeMedia = null;
    notifyListeners();
  }

  bool _sameUrl(Uri a, Uri b) => a.toString() == b.toString();

  bool _supportedBrowserUri(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  @override
  void dispose() {
    _castCleanup?.call();
    _castCleanup = null;
    super.dispose();
  }
}
