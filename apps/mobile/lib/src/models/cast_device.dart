class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });

  final String id;
  final String name;
  final String host;
  final int port;

  Uri uri(String path) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path.startsWith('/') ? path : '/$path',
      );
}

class CastTarget {
  const CastTarget({
    required this.device,
    required this.pairingCode,
  });

  final CastDevice device;
  final String pairingCode;
}
