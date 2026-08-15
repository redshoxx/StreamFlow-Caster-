import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReceiverCredentialStore {
  ReceiverCredentialStore([SharedPreferencesAsync? preferences])
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const _prefix = 'streamflow.receiver.pairing.v1.';
  final SharedPreferencesAsync _preferences;

  Future<String?> load(String deviceId) async {
    final value = await _preferences.getString(_key(deviceId));
    return _isValid(value) ? value : null;
  }

  Future<void> save(String deviceId, String code) {
    if (!_isValid(code)) {
      throw ArgumentError.value(code, 'code', 'Pairing code must contain exactly 8 digits.');
    }
    return _preferences.setString(_key(deviceId), code);
  }

  Future<void> remove(String deviceId) => _preferences.remove(_key(deviceId));

  String _key(String deviceId) =>
      '$_prefix${base64Url.encode(utf8.encode(deviceId)).replaceAll('=', '')}';

  bool _isValid(String? value) =>
      value != null && RegExp(r'^\d{8}$').hasMatch(value);
}
