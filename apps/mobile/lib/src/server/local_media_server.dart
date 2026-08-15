import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';

class LocalMediaServer {
  HttpServer? _server;
  final Map<String, File> _files = {};

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<Uri> expose(File file, String lanHost) async {
    if (!await file.exists()) throw ArgumentError('File does not exist.');
    await start();
    final token = _token();
    _files[token] = file;
    return Uri.parse('http://$lanHost:${_server!.port}/media/$token');
  }

  Future<void> stop() async {
    _files.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.pathSegments.length != 2 || request.uri.pathSegments.first != 'media') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final token = request.uri.pathSegments[1];
    final file = _files[token];
    if (file == null || !await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final length = await file.length();
    final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
    request.response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, mime)
      ..set('Cache-Control', 'no-store');

    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = length - 1;

    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      final parsedStart = int.tryParse(parts.first);
      final parsedEnd = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (parsedStart != null) start = parsedStart;
      if (parsedEnd != null) end = min(parsedEnd, length - 1);
      if (start < 0 || start >= length || end < start) {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }

    final contentLength = end - start + 1;
    request.response.contentLength = contentLength;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    await request.response.addStream(file.openRead(start, end + 1));
    await request.response.close();
  }

  String _token() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
