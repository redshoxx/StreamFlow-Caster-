import 'dart:async';

import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import '../cast/device_discovery_service.dart';
import '../models/cast_device.dart';
import 'cast_remote_sheet.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.controller});

  final StreamFlowController controller;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _discovery = DeviceDiscoveryService();
  StreamSubscription<List<CastDevice>>? _subscription;
  List<CastDevice> _devices = const [];
  var _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = _discovery.devices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _discovery.start();
    } catch (_) {
      if (mounted) setState(() => _error = 'Gerätesuche konnte nicht gestartet werden.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferredId = widget.controller.preferredDevice?.id;
    final activeId = widget.controller.activeDevice?.id;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _start,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Geräte', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Text('StreamFlow Receiver im lokalen Netzwerk'),
                    ],
                  ),
                ),
                IconButton(onPressed: _scanning ? null : _start, icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
            if (_scanning) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 18),
            if (widget.controller.isCasting)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cast_connected),
                  title: Text(widget.controller.activeDevice!.name),
                  subtitle: Text('Aktive Wiedergabe • ${widget.controller.activeMedia!.displayName}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showCastRemoteSheet(context, widget.controller),
                ),
              ),
            if (_devices.isEmpty && !_scanning)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.tv_off_outlined, size: 44),
                      const SizedBox(height: 12),
                      Text('Kein StreamFlow TV gefunden', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Smartphone und Fernseher müssen im selben lokalen Netzwerk sein.', textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(onPressed: _start, icon: const Icon(Icons.radar), label: const Text('Erneut suchen')),
                    ],
                  ),
                ),
              ),
            for (final device in _devices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(activeId == device.id ? Icons.cast_connected : Icons.tv_rounded),
                    ),
                    title: Text(device.name),
                    subtitle: Text(activeId == device.id
                        ? 'Aktiv verbunden'
                        : preferredId == device.id
                            ? 'Bevorzugtes Gerät'
                            : '${device.host}:${device.port}'),
                    trailing: preferredId == device.id
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      widget.controller.setPreferredDevice(device);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} als bevorzugtes Gerät gewählt.')));
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
