import 'dart:async';
import 'dart:io';

import 'package:upnp_client/upnp_client.dart';

import '../models/cast_device.dart';
import '../models/detected_media.dart';

class DlnaPlaybackStatus {
  const DlnaPlaybackStatus({
    required this.playing,
    required this.position,
    required this.duration,
    required this.volume,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
}

class DlnaCastService {
  DlnaCastService._();

  static final DlnaCastService instance = DlnaCastService._();

  static const _mediaRendererTarget =
      'urn:schemas-upnp-org:device:MediaRenderer:1';

  final _controller = StreamController<List<CastDevice>>.broadcast();
  final Map<String, Device> _nativeDevices = {};
  DeviceDiscoverer? _discoverer;
  StreamSubscription<Device>? _subscription;
  bool _starting = false;

  Stream<List<CastDevice>> get devices => _controller.stream;

  Future<void> start() async {
    if (_starting || _discoverer != null) return;
    _starting = true;
    final discoverer = DeviceDiscoverer();
    try {
      await discoverer.start(
        addressTypes: const [InternetAddressType.IPv4],
      );
      _discoverer = discoverer;
      _subscription = discoverer.devices.listen(
        _upsert,
        onError: (_) {},
      );

      final initial = await discoverer.getDevices(
        timeout: const Duration(seconds: 4),
        searchTarget: _mediaRendererTarget,
      );
      for (final device in initial) {
        _upsert(device);
      }
    } catch (_) {
      discoverer.dispose();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  void _upsert(Device device) {
    if (device.avTransportService() == null) return;
    final description = device.description;
    final id = description?.uuid ?? device.url ?? device.hashCode.toString();
    final name = description?.friendlyName?.trim();
    final model = description?.modelName?.trim();
    final endpoint = Uri.tryParse(device.url ?? device.urlBase ?? '');

    _nativeDevices[id] = device;
    final list = _nativeDevices.entries
        .map(
          (entry) {
            final native = entry.value;
            final nativeDescription = native.description;
            final nativeEndpoint =
                Uri.tryParse(native.url ?? native.urlBase ?? '');
            return CastDevice(
              id: entry.key,
              name: nativeDescription?.friendlyName?.trim().isNotEmpty == true
                  ? nativeDescription!.friendlyName!.trim()
                  : nativeDescription?.modelName?.trim().isNotEmpty == true
                      ? nativeDescription!.modelName!.trim()
                      : 'DLNA TV',
              host: nativeEndpoint?.host ?? '',
              port: nativeEndpoint?.hasPort == true ? nativeEndpoint!.port : 0,
              protocol: CastProtocol.dlna,
              modelName: nativeDescription?.modelName,
            );
          },
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!_controller.isClosed) _controller.add(List.unmodifiable(list));

    // Touch local variables to keep analyzer strict about discovery metadata.
    if ((name?.isEmpty ?? true) && (model?.isEmpty ?? true) && endpoint == null) {
      return;
    }
  }

  Device _device(CastDevice device) {
    final native = _nativeDevices[device.id];
    if (native == null) {
      throw StateError('DLNA device is no longer available.');
    }
    return native;
  }

  Future<void> load(CastDevice device, DetectedMedia media) async {
    await start();
    final transport = _device(device).avTransportService();
    if (transport == null) {
      throw StateError('Device does not provide AVTransport.');
    }
    await transport.setAVTransportURI(media.url.toString());
    await transport.play();
  }

  Future<DlnaPlaybackStatus> status(CastDevice device) async {
    final native = _device(device);
    final transport = native.avTransportService();
    if (transport == null) throw StateError('AVTransport unavailable.');

    final positionInfo = await transport.getPositionInfo();
    final transportInfo = await transport.getTransportInfo();
    final rendering = native.renderingControlService();
    final volume = rendering == null ? 100 : await rendering.getVolume();

    return DlnaPlaybackStatus(
      playing: transportInfo.currentTransportState == TransportState.playing,
      position: _parseTime(positionInfo.relTime),
      duration: _parseTime(positionInfo.trackDuration),
      volume: (volume.clamp(0, 100) / 100).toDouble(),
    );
  }

  Future<void> play(CastDevice device) async {
    final transport = _device(device).avTransportService();
    if (transport == null) throw StateError('AVTransport unavailable.');
    await transport.play();
  }

  Future<void> pause(CastDevice device) async {
    final transport = _device(device).avTransportService();
    if (transport == null) throw StateError('AVTransport unavailable.');
    await transport.pause();
  }

  Future<void> stop(CastDevice device) async {
    final transport = _device(device).avTransportService();
    if (transport == null) throw StateError('AVTransport unavailable.');
    await transport.stop();
  }

  Future<void> seek(CastDevice device, Duration position) async {
    final transport = _device(device).avTransportService();
    if (transport == null) throw StateError('AVTransport unavailable.');
    await transport.seek(SeekMode.relTime, _formatTime(position));
  }

  Future<void> setVolume(CastDevice device, double volume) async {
    final rendering = _device(device).renderingControlService();
    if (rendering == null) return;
    await rendering.setVolume(volume: (volume.clamp(0.0, 1.0) * 100).round());
  }

  Duration _parseTime(String? value) {
    if (value == null || value.isEmpty || value == 'NOT_IMPLEMENTED') {
      return Duration.zero;
    }
    final parts = value.split(':');
    if (parts.length != 3) return Duration.zero;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = double.tryParse(parts[2]) ?? 0;
    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }

  String _formatTime(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> restart() async {
    await stopDiscovery();
    await start();
  }

  Future<void> stopDiscovery() async {
    await _subscription?.cancel();
    _subscription = null;
    final discoverer = _discoverer;
    _discoverer = null;
    discoverer?.stop();
    discoverer?.dispose();
    _nativeDevices.clear();
    if (!_controller.isClosed) _controller.add(const []);
  }
}
