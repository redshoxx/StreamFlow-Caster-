import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';

class LocalMediaServer {
  HttpServer? _server;
  File? _file;
  String? _token;
  String? _fileName;

  bool get isRunning => _server != null;

  Future<Uri> serve(File file, {required String fileName}) async {
    await stop();

    if (!await file.exists()) {
      throw const LocalMediaServerException(
        'Die ausgewählte Datei ist nicht mehr verfügbar.',
      );
    }

    final host = await _findLanAddress();
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    final token = _newToken();

    _file = file;
    _fileName = fileName;
    _token = token;
    _server = server;
    server.listen(
      (request) async {
        try {
          await _handleRequest(request);
        } catch (_) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
            await request.response.close();
          } catch (_) {
            // The response may already have been closed by a failed stream pipe.
          }
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );

    return Uri(
      scheme: 'http',
      host: host,
      port: server.port,
      pathSegments: ['media', token, fileName],
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final file = _file;
    final token = _token;
    if (file == null || token == null) {
      await _fail(request, HttpStatus.serviceUnavailable);
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length != 3 ||
        segments[0] != 'media' ||
        segments[1] != token) {
      await _fail(request, HttpStatus.notFound);
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    if (!await file.exists()) {
      await _fail(request, HttpStatus.notFound);
      return;
    }

    final length = await file.length();
    var start = 0;
    var end = length - 1;
    var partial = false;

    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.isNotEmpty) {
      final parsed = _parseRange(range, length);
      if (parsed == null) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$length',
        );
        await request.response.close();
        return;
      }
      start = parsed.$1;
      end = parsed.$2;
      partial = true;
    }

    final response = request.response;
    response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.contentType = ContentType.parse(
      lookupMimeType(_fileName ?? file.path) ?? 'application/octet-stream',
    );

    final contentLength = length == 0 ? 0 : end - start + 1;
    response.contentLength = contentLength;
    if (partial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }

    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }

    await file.openRead(start, end + 1).pipe(response);
  }

  (int, int)? _parseRange(String header, int length) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null || length <= 0) return null;

    final rawStart = match.group(1) ?? '';
    final rawEnd = match.group(2) ?? '';
    if (rawStart.isEmpty && rawEnd.isEmpty) return null;

    if (rawStart.isEmpty) {
      final suffixLength = int.tryParse(rawEnd);
      if (suffixLength == null || suffixLength <= 0) return null;
      final start = max(0, length - suffixLength);
      return (start, length - 1);
    }

    final start = int.tryParse(rawStart);
    if (start == null || start < 0 || start >= length) return null;

    final requestedEnd = rawEnd.isEmpty ? length - 1 : int.tryParse(rawEnd);
    if (requestedEnd == null || requestedEnd < start) return null;
    return (start, min(requestedEnd, length - 1));
  }

  Future<String> _findLanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final ordered = [...interfaces]
      ..sort((a, b) {
        final aPreferred = _isLikelyWifiInterface(a.name);
        final bPreferred = _isLikelyWifiInterface(b.name);
        if (aPreferred == bPreferred) return 0;
        return aPreferred ? -1 : 1;
      });

    InternetAddress? fallback;
    for (final interface in ordered) {
      for (final address in interface.addresses) {
        fallback ??= address;
        if (_isPrivateIpv4(address.address)) return address.address;
      }
    }

    if (fallback != null) return fallback.address;
    throw const LocalMediaServerException(
      'Keine lokale WLAN-Adresse gefunden. Prüfe die Netzwerkverbindung.',
    );
  }

  bool _isLikelyWifiInterface(String name) {
    final normalized = name.toLowerCase();
    return normalized == 'en0' ||
        normalized == 'en1' ||
        normalized.startsWith('wlan') ||
        normalized.contains('wifi') ||
        normalized.contains('wi-fi');
  }

  bool _isPrivateIpv4(String address) {
    if (address.startsWith('10.')) return true;
    if (address.startsWith('192.168.')) return true;
    final parts = address.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _fail(HttpRequest request, int statusCode) async {
    request.response.statusCode = statusCode;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await request.response.close();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _file = null;
    _token = null;
    _fileName = null;
    if (server != null) await server.close(force: true);
  }
}

class LocalMediaServerException implements Exception {
  const LocalMediaServerException(this.message);

  final String message;

  @override
  String toString() => message;
}
