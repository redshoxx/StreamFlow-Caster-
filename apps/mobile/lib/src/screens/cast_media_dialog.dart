import 'dart:async';

import 'package:flutter/material.dart';

import '../cast/device_discovery_service.dart';
import '../cast/receiver_client.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';

class CastMediaDialog extends StatefulWidget {
  const CastMediaDialog({super.key, required this.media});

  final DetectedMedia media;

  @override
  State<CastMediaDialog> createState() => _CastMediaDialogState();
}

class _CastMediaDialogState extends State<CastMediaDialog> {
  final _discovery = DeviceDiscoveryService();
  final _client = ReceiverClient();
  StreamSubscription<List<CastDevice>>? _subscription;
  List<CastDevice> _devices = const [];
  String? _error;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    _subscription = _discovery.devices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _start();
  }

  Future<void> _start() async {
    try {
      await _discovery.start();
    } catch (_) {
      if (mounted) setState(() => _error = 'Gerätesuche fehlgeschlagen.');
    }
  }

  Future<void> _cast(CastDevice device) async {
    setState(() {
      _connectingId = device.id;
      _error = null;
    });
    try {
      await _client.load(device, widget.media.url, title: widget.media.displayName);
      if (mounted) Navigator.of(context).pop(device);
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectingId = null;
          _error = 'Der Fernseher konnte den Stream nicht laden.';
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _discovery.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Auf Gerät abspielen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('StreamFlow TV wird gesucht …'),
                  ],
                ),
              )
            else
              ..._devices.map(
                (device) => ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(device.name),
                  subtitle: Text(device.host),
                  trailing: _connectingId == device.id
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  enabled: _connectingId == null,
                  onTap: () => _cast(device),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      ],
    );
  }
}
