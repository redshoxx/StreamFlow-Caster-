import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/cast/local_media_server.dart';

void main() {
  late Directory tempDirectory;
  late File mediaFile;
  late LocalMediaServer server;
  late HttpClient client;
  late Uri mediaUri;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('streamflow-media-test-');
    mediaFile = File('${tempDirectory.path}/sample.mp4');
    await mediaFile.writeAsBytes(utf8.encode('0123456789'), flush: true);
    server = LocalMediaServer(advertisedHost: '127.0.0.1');
    client = HttpClient();
    mediaUri = await server.serve(mediaFile, fileName: 'sample.mp4');
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await tempDirectory.delete(recursive: true);
  });

  test('serves the full file with range support advertised', () async {
    final request = await client.getUrl(mediaUri);
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(await _body(response), '0123456789');
  });

  test('serves an RFC byte range with 206 and content-range', () async {
    final request = await client.getUrl(mediaUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 2-5/10',
    );
    expect(await _body(response), '2345');
  });

  test('rejects an unsatisfiable byte range', () async {
    final request = await client.getUrl(mediaUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=99-120');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes */10',
    );
  });
}

Future<String> _body(HttpClientResponse response) =>
    utf8.decoder.bind(response).join();
