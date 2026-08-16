import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/models/cast_device.dart';

void main() {
  test('receiver URI handles IPv6 hosts safely', () {
    const device = CastDevice(
      id: 'tv',
      name: 'TV',
      host: 'fe80::1234',
      port: 38743,
    );

    expect(
      device.uri('/api/v1/status').toString(),
      'http://[fe80::1234]:38743/api/v1/status',
    );
  });

  test('receiver URI normalizes missing leading slash', () {
    const device = CastDevice(
      id: 'tv',
      name: 'TV',
      host: '192.168.1.20',
      port: 38743,
    );

    expect(
      device.uri('api/v1/health').toString(),
      'http://192.168.1.20:38743/api/v1/health',
    );
  });

  test('protocol labels remain stable for the device picker', () {
    expect(CastProtocol.streamFlow.label, 'StreamFlow');
    expect(CastProtocol.googleCast.label, 'Google Cast');
    expect(CastProtocol.dlna.label, 'DLNA / UPnP');
    expect(CastProtocol.airPlay.label, 'AirPlay');
  });

  test('protocol-only devices reject direct receiver HTTP URIs', () {
    const device = CastDevice(
      id: 'chromecast',
      name: 'Living Room',
      protocol: CastProtocol.googleCast,
    );

    expect(device.hasNetworkEndpoint, isFalse);
    expect(() => device.uri('/api/v1/status'), throwsStateError);
  });
}
