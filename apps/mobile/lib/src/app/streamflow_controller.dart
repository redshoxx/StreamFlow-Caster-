import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/browser_entry.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import '../storage/browser_library_store.dart';

class StreamFlowController extends ChangeNotifier {
  StreamFlowController({BrowserLibraryStore? browserLibraryStore})
      : _browserLibraryStore = browserLibraryStore ?? BrowserLibraryStore() {
    _browserLibraryReady = _loadBrowserLibrary();
  }

  static const _maxHistoryEntries = 100;
  static const _maxFavoriteEntries = 100;
  static const _maxDetectedMediaEntries = 200;

  final BrowserLibraryStore _browserLibraryStore;
  final List<DetectedMedia> _detectedMedia = <DetectedMedia>[];
  final List<BrowserEntry> _history = <BrowserEntry>[];
  final List<BrowserEntry> _favorites = <BrowserEntry>[];
  late final Future<void> _browserLibraryReady;
  Future<void> _storageWriteQueue = Future<void>.value();
  VoidCallback? _castCleanup;
  bool _browserLibraryLoaded = false;
  bool _disposed = false;

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

  String? _activePairingCode;
  String? get activePairingCode => _activePairingCode;

  bool get isCasting =>
      _activeDevice != null && _activeMedia != null && _activePairingCode != null;

  Future<void> _loadBrowserLibrary() async {
    try {
      final snapshot = await _browserLibraryStore.load();
      if (_disposed) return;
      _history
        ..clear()
        ..addAll(snapshot.history.take(_maxHistoryEntries));
      _favorites
        ..clear()
        ..addAll(snapshot.favorites.take(_maxFavoriteEntries));
    } catch (_) {
      // Corrupted or temporarily unavailable local storage must not block app startup.
    } finally {
      if (!_disposed) {
        _browserLibraryLoaded = true;
        notifyListeners();
      }
    }
  }

  void addDetectedMedia(DetectedMedia media) {
    if (_detectedMedia.contains(media)) return;
    _detectedMedia.insert(0, media);
    if (_detectedMedia.length > _maxDetectedMediaEntries) {
      _detectedMedia.removeRange(_maxDetectedMediaEntries, _detectedMedia.length);
    }
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
    await _browserLibraryReady;
    if (_disposed) return;

    _history.removeWhere((entry) => _sameUrl(entry.url, url));
    _history.insert(
      0,
      BrowserEntry(url: url, title: title, timestamp: DateTime.now()),
    );
    if (_history.length > _maxHistoryEntries) {
      _history.removeRange(_maxHistoryEntries, _history.length);
    }
    notifyListeners();
    await _enqueueStorageWrite(() => _browserLibraryStore.saveHistory(_history));
  }

  bool isFavorite(Uri? url) {
    if (url == null) return false;
    return _favorites.any((entry) => _sameUrl(entry.url, url));
  }

  Future<void> toggleFavorite(Uri url, String title) async {
    if (!_supportedBrowserUri(url)) return;
    await _browserLibraryReady;
    if (_disposed) return;

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
    await _enqueueStorageWrite(() => _browserLibraryStore.saveFavorites(_favorites));
  }

  Future<void> removeFavorite(Uri url) async {
    await _browserLibraryReady;
    if (_disposed) return;

    final before = _favorites.length;
    _favorites.removeWhere((entry) => _sameUrl(entry.url, url));
    if (_favorites.length == before) return;
    notifyListeners();
    await _enqueueStorageWrite(() => _browserLibraryStore.saveFavorites(_favorites));
  }

  Future<void> removeHistoryEntry(Uri url) async {
    await _browserLibraryReady;
    if (_disposed) return;

    final before = _history.length;
    _history.removeWhere((entry) => _sameUrl(entry.url, url));
    if (_history.length == before) return;
    notifyListeners();
    await _enqueueStorageWrite(() => _browserLibraryStore.saveHistory(_history));
  }

  Future<void> clearHistory() async {
    await _browserLibraryReady;
    if (_disposed || _history.isEmpty) return;
    _history.clear();
    notifyListeners();
    await _enqueueStorageWrite(() => _browserLibraryStore.saveHistory(_history));
  }

  Future<void> _enqueueStorageWrite(Future<void> Function() write) {
    _storageWriteQueue = _storageWriteQueue.then((_) async {
      try {
        await write();
      } catch (_) {
        // Local persistence errors must not interrupt the active browsing session.
      }
    });
    return _storageWriteQueue;
  }

  void setPreferredDevice(CastDevice device) {
    if (_preferredDevice?.id == device.id &&
        _preferredDevice?.host == device.host &&
        _preferredDevice?.port == device.port) {
      return;
    }
    _preferredDevice = device;
    notifyListeners();
  }

  void startCasting(
    CastDevice device,
    DetectedMedia media, {
    required String pairingCode,
    VoidCallback? onEnd,
  }) {
    _castCleanup?.call();
    _castCleanup = onEnd;
    _preferredDevice = device;
    _activeDevice = device;
    _activeMedia = media;
    _activePairingCode = pairingCode;
    notifyListeners();
  }

  void endCasting() {
    if (!isCasting && _castCleanup == null) return;
    _castCleanup?.call();
    _castCleanup = null;
    _activeDevice = null;
    _activeMedia = null;
    _activePairingCode = null;
    notifyListeners();
  }

  bool _sameUrl(Uri a, Uri b) => a.toString() == b.toString();

  bool _supportedBrowserUri(Uri uri) =>
      uri.scheme == 'http' || uri.scheme == 'https';

  @override
  void dispose() {
    _disposed = true;
    _castCleanup?.call();
    _castCleanup = null;
    _activePairingCode = null;
    super.dispose();
  }
}
