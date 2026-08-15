import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../models/cast_device.dart';

class DeviceDiscoveryService {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final _controller = StreamController<List<CastDevice>>.broadcast();
  final Map<String, CastDevice> _devices = {};
  var _generation = 0;
  var _disposed = false;

  Stream<List<CastDevice>> get devices => _controller.stream;

  Future<void> start() async {
    if (_disposed) throw StateError('DeviceDiscoveryService is disposed.');

    await _stopInternal();
    final generation = ++_generation;
    final discovery = BonsoirDiscovery(type: '_streamflow._tcp');
    await discovery.initialize();
    if (_disposed || generation != _generation) {
      await discovery.stop();
      return;
    }
    _discovery = discovery;

    _subscription = discovery.eventStream?.listen(
      (event) => unawaited(_handleEvent(event, discovery, generation)),
      onError: (_) {},
    );

    await discovery.start();
  }

  Future<void> _handleEvent(
    BonsoirDiscoveryEvent event,
    BonsoirDiscovery discovery,
    int generation,
  ) async {
    if (_disposed || generation != _generation) return;

    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        try {
          await event.service.resolve(discovery.serviceResolver);
        } catch (_) {
          return;
        }
        break;
      case BonsoirDiscoveryServiceResolvedEvent():
        _upsert(event.service, generation);
        break;
      case BonsoirDiscoveryServiceUpdatedEvent():
        _upsert(event.service, generation);
        break;
      case BonsoirDiscoveryServiceLostEvent():
        if (_disposed || generation != _generation) return;
        _devices.remove(event.service.name);
        _emit();
        break;
      default:
        break;
    }
  }

  void _upsert(BonsoirService service, int generation) {
    if (_disposed || generation != _generation || service.hostAddresses.isEmpty) {
      return;
    }

    final host = service.hostAddresses.firstWhere(
      (address) => !address.contains(':'),
      orElse: () => service.hostAddresses.first,
    );

    _devices[service.name] = CastDevice(
      id: service.name,
      name: service.name,
      host: host,
      port: service.port,
    );
    _emit();
  }

  void _emit() {
    if (_disposed || _controller.isClosed) return;
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _controller.add(List.unmodifiable(list));
  }

  Future<void> _stopInternal() async {
    _generation += 1;
    final subscription = _subscription;
    final discovery = _discovery;
    _subscription = null;
    _discovery = null;

    await subscription?.cancel();
    if (discovery != null) {
      try {
        await discovery.stop();
      } catch (_) {}
    }
    _devices.clear();
    _emit();
  }

  Future<void> stop() => _stopInternal();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopInternal();
    await _controller.close();
  }
}
