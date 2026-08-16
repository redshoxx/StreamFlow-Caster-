import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../models/cast_device.dart';
import 'dlna_cast_service.dart';
import 'google_cast_service.dart';

class DeviceDiscoveryService {
  BonsoirDiscovery? _streamFlowDiscovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _streamFlowSubscription;
  StreamSubscription<List<CastDevice>>? _googleSubscription;
  StreamSubscription<List<CastDevice>>? _dlnaSubscription;

  final _controller = StreamController<List<CastDevice>>.broadcast();
  final Map<String, CastDevice> _streamFlowDevices = {};
  final Map<String, CastDevice> _googleDevices = {};
  final Map<String, CastDevice> _dlnaDevices = {};
  var _generation = 0;
  var _disposed = false;

  Stream<List<CastDevice>> get devices => _controller.stream;

  Future<void> start() async {
    if (_disposed) throw StateError('DeviceDiscoveryService is disposed.');

    await _stopInternal(clearExternal: false);
    final generation = ++_generation;

    _googleSubscription ??= GoogleCastService.instance.devices.listen(
      (devices) {
        if (_disposed) return;
        _googleDevices
          ..clear()
          ..addEntries(devices.map((device) => MapEntry(device.id, device)));
        _emit();
      },
      onError: (_) {},
    );
    _dlnaSubscription ??= DlnaCastService.instance.devices.listen(
      (devices) {
        if (_disposed) return;
        _dlnaDevices
          ..clear()
          ..addEntries(devices.map((device) => MapEntry(device.id, device)));
        _emit();
      },
      onError: (_) {},
    );

    final starts = <Future<void>>[
      _startStreamFlow(generation),
      GoogleCastService.instance.initialize(),
      DlnaCastService.instance.restart(),
    ];

    Object? firstError;
    for (final future in starts) {
      try {
        await future;
      } catch (error) {
        firstError ??= error;
      }
    }

    // One protocol failing must not hide devices found by the others.
    if (_allDevicesEmpty && firstError != null) throw firstError;
  }

  bool get _allDevicesEmpty =>
      _streamFlowDevices.isEmpty && _googleDevices.isEmpty && _dlnaDevices.isEmpty;

  Future<void> _startStreamFlow(int generation) async {
    final discovery = BonsoirDiscovery(type: '_streamflow._tcp');
    var adopted = false;

    try {
      await discovery.initialize();
      if (_disposed || generation != _generation) {
        await _safeStop(discovery);
        return;
      }

      _streamFlowDiscovery = discovery;
      adopted = true;
      _streamFlowSubscription = discovery.eventStream?.listen(
        (event) => unawaited(_handleStreamFlowEvent(event, discovery, generation)),
        onError: (_) {},
      );
      await discovery.start();
    } catch (_) {
      if (adopted && !_disposed && generation == _generation) {
        await _stopStreamFlow();
      } else {
        await _safeStop(discovery);
      }
      rethrow;
    }
  }

  Future<void> _handleStreamFlowEvent(
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
        _upsertStreamFlow(event.service, generation);
        break;
      case BonsoirDiscoveryServiceUpdatedEvent():
        _upsertStreamFlow(event.service, generation);
        break;
      case BonsoirDiscoveryServiceLostEvent():
        if (_disposed || generation != _generation) return;
        _streamFlowDevices.remove(event.service.name);
        _emit();
        break;
      default:
        break;
    }
  }

  void _upsertStreamFlow(BonsoirService service, int generation) {
    if (_disposed || generation != _generation || service.hostAddresses.isEmpty) {
      return;
    }

    final host = service.hostAddresses.firstWhere(
      (address) => !address.contains(':'),
      orElse: () => service.hostAddresses.first,
    );

    _streamFlowDevices[service.name] = CastDevice(
      id: service.name,
      name: service.name,
      host: host,
      port: service.port,
      protocol: CastProtocol.streamFlow,
      modelName: 'StreamFlow TV Receiver',
    );
    _emit();
  }

  void _emit() {
    if (_disposed || _controller.isClosed) return;
    final seen = <String>{};
    final list = <CastDevice>[];
    for (final device in [
      ..._streamFlowDevices.values,
      ..._googleDevices.values,
      ..._dlnaDevices.values,
    ]) {
      final key = '${device.protocol.name}:${device.id}';
      if (seen.add(key)) list.add(device);
    }
    list.sort((a, b) {
      final protocol = a.protocol.index.compareTo(b.protocol.index);
      return protocol != 0 ? protocol : a.name.compareTo(b.name);
    });
    _controller.add(List.unmodifiable(list));
  }

  Future<void> _safeStop(BonsoirDiscovery discovery) async {
    try {
      await discovery.stop();
    } catch (_) {}
  }

  Future<void> _stopStreamFlow() async {
    final subscription = _streamFlowSubscription;
    final discovery = _streamFlowDiscovery;
    _streamFlowSubscription = null;
    _streamFlowDiscovery = null;
    await subscription?.cancel();
    if (discovery != null) await _safeStop(discovery);
    _streamFlowDevices.clear();
  }

  Future<void> _stopInternal({required bool clearExternal}) async {
    _generation += 1;
    await _stopStreamFlow();
    if (clearExternal) {
      await DlnaCastService.instance.stopDiscovery();
      _googleDevices.clear();
      _dlnaDevices.clear();
    }
    _emit();
  }

  Future<void> stop() => _stopInternal(clearExternal: true);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _stopStreamFlow();
    await _googleSubscription?.cancel();
    await _dlnaSubscription?.cancel();
    _googleSubscription = null;
    _dlnaSubscription = null;
    await _controller.close();
  }
}
