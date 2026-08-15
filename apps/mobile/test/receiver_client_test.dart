import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamflow/src/cast/receiver_client.dart';
import 'package:streamflow/src/models/cast_device.dart';

void main() {
  const device = CastDevice(
    id: 'tv',
    name: 'TV',
    host: '192.168.1.20',
    port: 38743,
  );

  test('status sends pairing code header', () async {
    final mock = MockClient((request) async {
      expect(request.headers['x-streamflow-pairing-code'], '12345678');
      expect(request.url.path, '/api/v1/status');
      return http.Response('{"isPlaying":false}', 200);
    });
    final client = ReceiverClient(client: mock);

    final status = await client.status(device, pairingCode: '12345678');
    expect(status['isPlaying'], isFalse);
    client.close();
  });

  test('401 is surfaced as pairing-required exception', () async {
    final client = ReceiverClient(
      client: MockClient((_) async => http.Response('{"error":"pairing_required"}', 401)),
    );

    await expectLater(
      client.status(device, pairingCode: '00000000'),
      throwsA(
        isA<ReceiverException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.isPairingRequired, 'isPairingRequired', isTrue),
      ),
    );
    client.close();
  });

  test('invalid JSON is rejected', () async {
    final client = ReceiverClient(
      client: MockClient((_) async => http.Response('not-json', 200)),
    );

    await expectLater(
      client.status(device, pairingCode: '12345678'),
      throwsA(isA<ReceiverException>()),
    );
    client.close();
  });
}
