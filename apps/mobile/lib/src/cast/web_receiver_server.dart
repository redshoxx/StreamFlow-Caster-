import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/cast_device.dart';

class WebReceiverSession {
  const WebReceiverSession({
    required this.device,
    required this.pairingCode,
    required this.receiverUrl,
  });

  final CastDevice device;
  final String pairingCode;
  final Uri receiverUrl;
}

class WebReceiverServer {
  WebReceiverServer._();

  static final WebReceiverServer instance = WebReceiverServer._();

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  WebReceiverSession? _session;

  String? _mediaUrl;
  String _title = '';
  bool _desiredPlaying = false;
  bool _reportedPlaying = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 1.0;
  int _revision = 0;
  DateTime? _lastReceiverReport;
  String? _receiverError;

  Future<WebReceiverSession> start() async {
    final existing = _session;
    if (existing != null && _server != null) return existing;

    final host = await _localIpv4();
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );
    final code = _randomCode();
    final device = CastDevice(
      id: 'web-browser-$host:${server.port}',
      name: 'Webbrowser-Empfänger',
      host: host,
      port: server.port,
      protocol: CastProtocol.streamFlow,
      modelName: 'TV-Webbrowser',
    );
    final receiverUrl = Uri(
      scheme: 'http',
      host: host,
      port: server.port,
      path: '/receiver',
      queryParameters: {'code': code},
    );

    _server = server;
    _session = WebReceiverSession(
      device: device,
      pairingCode: code,
      receiverUrl: receiverUrl,
    );
    _subscription = server.listen(
      (request) => unawaited(_handle(request)),
      onError: (_) {},
      cancelOnError: false,
    );
    return _session!;
  }

  Future<void> stop() async {
    final subscription = _subscription;
    final server = _server;
    _subscription = null;
    _server = null;
    _session = null;
    await subscription?.cancel();
    await server?.close(force: true);
    _mediaUrl = null;
    _title = '';
    _desiredPlaying = false;
    _reportedPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    _volume = 1.0;
    _revision = 0;
    _lastReceiverReport = null;
    _receiverError = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/receiver') {
        await _serveReceiver(request);
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/health') {
        _json(request.response, HttpStatus.ok, {
          'protocol': 2,
          'pairingRequired': true,
          'version': '1.1.0',
          'receiver': 'web-browser',
        });
        return;
      }

      if (!_authorized(request)) {
        _json(request.response, HttpStatus.unauthorized, {
          'error': 'pairing_required',
        });
        return;
      }

      if (request.method == 'GET' && path == '/api/v1/status') {
        _status(request.response);
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/load') {
        final body = await _readJson(request);
        final url = body['url']?.toString().trim();
        if (url == null || url.isEmpty || Uri.tryParse(url) == null) {
          _json(request.response, HttpStatus.badRequest, {'error': 'invalid_url'});
          return;
        }
        _mediaUrl = url;
        _title = body['title']?.toString() ?? '';
        _positionMs = 0;
        _durationMs = 0;
        _desiredPlaying = true;
        _reportedPlaying = false;
        _receiverError = null;
        _revision += 1;
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/play') {
        _desiredPlaying = true;
        _revision += 1;
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/pause') {
        _desiredPlaying = false;
        _revision += 1;
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/stop') {
        _desiredPlaying = false;
        _reportedPlaying = false;
        _mediaUrl = null;
        _positionMs = 0;
        _durationMs = 0;
        _revision += 1;
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/seek') {
        final body = await _readJson(request);
        _positionMs = ((body['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31);
        _revision += 1;
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/volume') {
        final body = await _readJson(request);
        _volume = ((body['volume'] as num?)?.toDouble() ?? _volume)
            .clamp(0.0, 1.0)
            .toDouble();
        _revision += 1;
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }
      if (request.method == 'POST' && path == '/web/v1/report') {
        final body = await _readJson(request);
        _reportedPlaying = body['isPlaying'] == true;
        _positionMs = ((body['positionMs'] as num?)?.toInt() ?? _positionMs)
            .clamp(0, 1 << 31);
        _durationMs = ((body['durationMs'] as num?)?.toInt() ?? _durationMs)
            .clamp(0, 1 << 31);
        _receiverError = body['error']?.toString().trim();
        if (_receiverError?.isEmpty == true) _receiverError = null;
        _lastReceiverReport = DateTime.now();
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }

      _json(request.response, HttpStatus.notFound, {'error': 'not_found'});
    } catch (_) {
      if (!request.response.headersSent) {
        _json(request.response, HttpStatus.internalServerError, {
          'error': 'receiver_server_error',
        });
      } else {
        await request.response.close();
      }
    }
  }

  bool _authorized(HttpRequest request) {
    final expected = _session?.pairingCode;
    if (expected == null) return false;
    final header = request.headers.value('x-streamflow-pairing-code');
    final query = request.uri.queryParameters['code'];
    return header == expected || query == expected;
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Expected JSON object');
  }

  void _status(HttpResponse response) {
    final receiverRecentlySeen = _lastReceiverReport != null &&
        DateTime.now().difference(_lastReceiverReport!) < const Duration(seconds: 5);
    _json(response, HttpStatus.ok, {
      'isPlaying': receiverRecentlySeen ? _reportedPlaying : _desiredPlaying,
      'positionMs': _positionMs,
      'durationMs': _durationMs,
      'volume': _volume,
      'title': _title,
      'url': _mediaUrl,
      'revision': _revision,
      'error': _receiverError,
      'receiverConnected': receiverRecentlySeen,
    });
  }

  Future<void> _serveReceiver(HttpRequest request) async {
    final code = request.uri.queryParameters['code'];
    if (code == null || code != _session?.pairingCode) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('Ungültiger StreamFlow Empfänger-Link.');
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.html;
    request.response.headers.set('cache-control', 'no-store');
    request.response.write(_receiverHtml(code));
    await request.response.close();
  }

  void _json(HttpResponse response, int status, Map<String, dynamic> body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.write(jsonEncode(body));
    unawaited(response.close());
  }

  Future<String> _localIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where((address) => !address.isLoopback)
        .map((address) => address.address)
        .toList();
    if (addresses.isEmpty) {
      throw const SocketException('No local IPv4 address available.');
    }
    return addresses.firstWhere(_isPrivateIpv4, orElse: () => addresses.first);
  }

  bool _isPrivateIpv4(String address) {
    if (address.startsWith('10.') || address.startsWith('192.168.')) return true;
    final parts = address.split('.');
    if (parts.length != 4 || parts.first != '172') return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  String _randomCode() {
    final random = Random.secure();
    return List.generate(8, (_) => random.nextInt(10)).join();
  }

  String _receiverHtml(String code) => '''<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
  <title>StreamFlow Web Receiver</title>
  <style>
    html,body{margin:0;width:100%;height:100%;background:#05070b;color:#fff;font-family:system-ui,-apple-system,Segoe UI,sans-serif;overflow:hidden}
    main{width:100%;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;background:radial-gradient(circle at 50% 20%,#17243c 0,#05070b 55%)}
    video{width:100%;height:100%;object-fit:contain;background:#000;display:none}
    #idle{display:flex;flex-direction:column;align-items:center;gap:14px;text-align:center;padding:32px}
    #logo{width:84px;height:84px;border-radius:24px;background:#4b8ffb;display:grid;place-items:center;font-size:38px;font-weight:800}
    h1{font-size:32px;margin:0} p{opacity:.76;font-size:19px;margin:0;max-width:720px}
    #status{margin-top:10px;font-size:15px;opacity:.65}
  </style>
</head>
<body>
<main>
  <div id="idle">
    <div id="logo">▶</div>
    <h1>StreamFlow Web Receiver</h1>
    <p>Bereit. Wähle auf deinem Smartphone ein Video und starte die Übertragung.</p>
    <div id="status">Mit StreamFlow verbunden</div>
  </div>
  <video id="player" controls playsinline></video>
</main>
<script>
(() => {
  const code = ${jsonEncode(code)};
  const headers = {'x-streamflow-pairing-code': code};
  const player = document.getElementById('player');
  const idle = document.getElementById('idle');
  let loadedUrl = '';
  let revision = -1;
  let reportTimer = 0;

  const report = async (error) => {
    try {
      await fetch('/web/v1/report', {
        method: 'POST',
        headers: {...headers, 'content-type': 'application/json'},
        body: JSON.stringify({
          isPlaying: !player.paused && !player.ended,
          positionMs: Math.round((player.currentTime || 0) * 1000),
          durationMs: Number.isFinite(player.duration) ? Math.round(player.duration * 1000) : 0,
          error: error || ''
        })
      });
    } catch (_) {}
  };

  const sync = async () => {
    try {
      const response = await fetch('/api/v1/status', {headers, cache: 'no-store'});
      if (!response.ok) return;
      const state = await response.json();
      if (!state.url) {
        if (loadedUrl) {
          player.pause();
          player.removeAttribute('src');
          player.load();
          loadedUrl = '';
        }
        player.style.display = 'none';
        idle.style.display = 'flex';
        revision = state.revision;
        return;
      }

      idle.style.display = 'none';
      player.style.display = 'block';
      if (loadedUrl !== state.url) {
        loadedUrl = state.url;
        player.src = state.url;
        player.load();
        revision = -1;
      }

      if (state.revision !== revision) {
        revision = state.revision;
        const target = Math.max(0, (state.positionMs || 0) / 1000);
        if (Math.abs((player.currentTime || 0) - target) > 1.5) {
          try { player.currentTime = target; } catch (_) {}
        }
        if (typeof state.volume === 'number') {
          player.volume = Math.max(0, Math.min(1, state.volume));
        }
        if (state.isPlaying) {
          try { await player.play(); } catch (_) {}
        } else {
          player.pause();
        }
      }
    } catch (_) {}
  };

  player.addEventListener('error', () => {
    const mediaError = player.error;
    report(mediaError ? 'Medienfehler ' + mediaError.code : 'Medienfehler');
  });
  player.addEventListener('playing', () => report(''));
  player.addEventListener('pause', () => report(''));
  player.addEventListener('loadedmetadata', () => report(''));
  player.addEventListener('timeupdate', () => {
    const now = Date.now();
    if (now - reportTimer > 1000) {
      reportTimer = now;
      report('');
    }
  });

  setInterval(sync, 750);
  setInterval(() => report(''), 2000);
  sync();
})();
</script>
</body>
</html>''';
}
