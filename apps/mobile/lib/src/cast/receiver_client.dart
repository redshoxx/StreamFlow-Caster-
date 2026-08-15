import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/cast_device.dart';

class ReceiverClient {
  ReceiverClient({http.Client? client}) : _client = client ?? http.Client();

  static const _pairingHeader = 'x-streamflow-pairing-code';
  static const _timeout = Duration(seconds: 5);

  final http.Client _client;

  Future<void> load(
    CastDevice device,
    Uri mediaUrl, {
    required String pairingCode,
    String? title,
  }) =>
      _post(
        device,
        '/api/v1/load',
        {
          'url': mediaUrl.toString(),
          'title': title ?? '',
        },
        pairingCode: pairingCode,
      );

  Future<void> play(CastDevice device, {required String pairingCode}) =>
      _post(device, '/api/v1/play', const {}, pairingCode: pairingCode);

  Future<void> pause(CastDevice device, {required String pairingCode}) =>
      _post(device, '/api/v1/pause', const {}, pairingCode: pairingCode);

  Future<void> stop(CastDevice device, {required String pairingCode}) =>
      _post(device, '/api/v1/stop', const {}, pairingCode: pairingCode);

  Future<void> seek(
    CastDevice device,
    Duration position, {
    required String pairingCode,
  }) =>
      _post(
        device,
        '/api/v1/seek',
        {'positionMs': position.inMilliseconds},
        pairingCode: pairingCode,
      );

  Future<void> setVolume(
    CastDevice device,
    double volume, {
    required String pairingCode,
  }) =>
      _post(
        device,
        '/api/v1/volume',
        {'volume': volume.clamp(0.0, 1.0)},
        pairingCode: pairingCode,
      );

  Future<Map<String, dynamic>> health(CastDevice device) async {
    final response = await _client
        .get(device.uri('/api/v1/health'))
        .timeout(const Duration(seconds: 3));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> status(
    CastDevice device, {
    required String pairingCode,
  }) async {
    final response = await _client
        .get(
          device.uri('/api/v1/status'),
          headers: {_pairingHeader: pairingCode},
        )
        .timeout(_timeout);
    return _decodeResponse(response);
  }

  Future<void> _post(
    CastDevice device,
    String path,
    Map<String, dynamic> body, {
    required String pairingCode,
  }) async {
    final response = await _client
        .post(
          device.uri(path),
          headers: {
            'content-type': 'application/json',
            _pairingHeader: pairingCode,
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    _ensureSuccess(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    _ensureSuccess(response);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Converted to a receiver-specific exception below.
    }
    throw const ReceiverException('Receiver returned invalid JSON.');
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReceiverException(
        'Receiver returned ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
  }

  void close() => _client.close();
}

class ReceiverException implements Exception {
  const ReceiverException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isPairingRequired => statusCode == 401;

  @override
  String toString() => message;
}
