import 'dart:async';

import 'package:flutter/material.dart';

import '../cast/device_discovery_service.dart';
import '../models/cast_device.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

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
    } catch (e) {
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
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _start,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(child: Text('Geräte', style: Theme.of(context).textTheme.headlineMedium)),
                IconButton(onPressed: _scanning ? null : _start, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_scanning) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            if (_devices.isEmpty && !_scanning)
              const ListTile(
                leading: Icon(Icons.tv_off_outlined),
                title: Text('Kein StreamFlow TV gefunden'),
                subtitle: Text('Smartphone und TV müssen im selben lokalen Netzwerk sein.'),
              ),
            for (final device in _devices)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(device.name),
                  subtitle: Text('${device.host}:${device.port}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
