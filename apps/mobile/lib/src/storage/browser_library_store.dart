import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/browser_entry.dart';

class BrowserLibrarySnapshot {
  const BrowserLibrarySnapshot({
    required this.history,
    required this.favorites,
  });

  final List<BrowserEntry> history;
  final List<BrowserEntry> favorites;
}

class BrowserLibraryStore {
  BrowserLibraryStore([this._preferences]);

  static const _historyKey = 'streamflow.browser.history.v1';
  static const _favoritesKey = 'streamflow.browser.favorites.v1';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  Future<BrowserLibrarySnapshot> load() async {
    final values = await Future.wait<String?>([
      _prefs.getString(_historyKey),
      _prefs.getString(_favoritesKey),
    ]);

    return BrowserLibrarySnapshot(
      history: _decode(values[0]),
      favorites: _decode(values[1]),
    );
  }

  Future<void> saveHistory(List<BrowserEntry> entries) =>
      _prefs.setString(_historyKey, _encode(entries));

  Future<void> saveFavorites(List<BrowserEntry> entries) =>
      _prefs.setString(_favoritesKey, _encode(entries));

  String _encode(List<BrowserEntry> entries) =>
      jsonEncode(entries.map((entry) => entry.toJson()).toList(growable: false));

  List<BrowserEntry> _decode(String? value) {
    if (value == null || value.isEmpty) return <BrowserEntry>[];

    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return <BrowserEntry>[];
      return decoded
          .map(BrowserEntry.fromJson)
          .whereType<BrowserEntry>()
          .toList(growable: true);
    } catch (_) {
      return <BrowserEntry>[];
    }
  }
}
