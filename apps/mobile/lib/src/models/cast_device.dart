enum CastProtocol { streamFlow, googleCast, dlna, airPlay }

extension CastProtocolLabel on CastProtocol {
  String get label => switch (this) {
        CastProtocol.streamFlow => 'StreamFlow',
        CastProtocol.googleCast => 'Google Cast',
        CastProtocol.dlna => 'DLNA / UPnP',
        CastProtocol.airPlay => 'AirPlay',
      };
}

class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    this.host = '',
    this.port = 0,
    this.protocol = CastProtocol.streamFlow,
    this.modelName,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final CastProtocol protocol;
  final String? modelName;

  bool get hasNetworkEndpoint => host.isNotEmpty && port > 0;

  Uri uri(String path) {
    if (!hasNetworkEndpoint) {
      throw StateError('$name has no direct HTTP endpoint.');
    }
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: path.startsWith('/') ? path : '/$path',
    );
  }
}

class CastTarget {
  const CastTarget({
    required this.device,
    this.pairingCode,
  });

  final CastDevice device;
  final String? pairingCode;
}
