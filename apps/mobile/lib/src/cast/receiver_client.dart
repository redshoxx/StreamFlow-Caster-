import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/cast_device.dart';

class ReceiverClient {
  ReceiverClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> load(CastDevice device, Uri mediaUrl, {String? title}) =>
      _post(device, '/api/v1/load', {
        'url': mediaUrl.toString(),
        'title': title ?? '',
      });

  Future<void> play(CastDevice device) => _post(device, '/api/v1/play', const {});
  Future<void> pause(CastDevice device) => _post(device, '/api/v1/pause', const {});
  Future<void> stop(CastDevice device) => _post(device, '/api/v1/stop', const {});
  Future<void> seek(CastDevice device, Duration position) =>
      _post(device, '/api/v1/seek', {'positionMs': position.inMilliseconds});
  Future<void> setVolume(CastDevice device, double volume) =>
      _post(device, '/api/v1/volume', {'volume': volume.clamp(0.0, 1.0)});

  Future<Map<String, dynamic>> status(CastDevice device) async {
    final response = await _client
        .get(device.uri('/api/v1/status'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReceiverException('Receiver returned ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _post(CastDevice device, String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          device.uri(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReceiverException('Receiver returned ${response.statusCode}.');
    }
  }

  void close() => _client.close();
}

class ReceiverException implements Exception {
  const ReceiverException(this.message);
  final String message;

  @override
  String toString() => message;
}
