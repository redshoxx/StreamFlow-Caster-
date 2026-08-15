import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../models/cast_device.dart';

class DeviceDiscoveryService {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final _controller = StreamController<List<CastDevice>>.broadcast();
  final Map<String, CastDevice> _devices = {};

  Stream<List<CastDevice>> get devices => _controller.stream;

  Future<void> start() async {
    await stop();
    final discovery = BonsoirDiscovery(type: '_streamflow._tcp');
    await discovery.initialize();
    _discovery = discovery;

    _subscription = discovery.eventStream?.listen((event) async {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          final service = event.service;
          if (service != null) {
            await service.resolve(discovery.serviceResolver);
          }
          break;
        case BonsoirDiscoveryServiceResolvedEvent():
          _upsert(event.service);
          break;
        case BonsoirDiscoveryServiceUpdatedEvent():
          _upsert(event.service);
          break;
        case BonsoirDiscoveryServiceLostEvent():
          final service = event.service;
          if (service != null) {
            _devices.remove(service.name);
            _emit();
          }
          break;
        default:
          break;
      }
    });

    await discovery.start();
  }

  void _upsert(BonsoirService service) {
    if (service.hostAddresses.isEmpty) return;
    final host = service.hostAddresses.first;

    _devices[service.name] = CastDevice(
      id: service.name,
      name: service.name,
      host: host,
      port: service.port,
    );
    _emit();
  }

  void _emit() {
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _controller.add(List.unmodifiable(list));
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
    _devices.clear();
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
