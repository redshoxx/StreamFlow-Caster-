import 'dart:async';
import 'dart:io';

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
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _discovery.start();
    } catch (_) {
      if (mounted && _devices.isEmpty) {
        setState(() {
          _error = 'Keine Gerätesuche konnte gestartet werden. Prüfe WLAN, lokale Netzwerkfreigaben und ob der Fernseher im selben Netzwerk erreichbar ist.';
        });
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_discovery.dispose());
    super.dispose();
  }

  bool _matches(CastDevice? a, CastDevice b) =>
      a != null && a.id == b.id && a.protocol == b.protocol;

  @override
  Widget build(BuildContext context) {
    final preferred = widget.controller.preferredDevice;
    final active = widget.controller.activeDevice;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
                      Text(
                        'Geräte',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'StreamFlow TV, Chromecast und DLNA automatisch erkennen',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Neu suchen',
                  onPressed: _scanning ? null : _start,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _ProtocolChip(icon: Icons.tv_rounded, label: 'StreamFlow'),
                const _ProtocolChip(icon: Icons.cast_rounded, label: 'Google Cast'),
                const _ProtocolChip(
                  icon: Icons.connected_tv_rounded,
                  label: 'DLNA / UPnP',
                ),
                if (Platform.isIOS)
                  const _ProtocolChip(
                    icon: Icons.airplay_rounded,
                    label: 'AirPlay',
                  ),
              ],
            ),
            if (_scanning) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: colors.error),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            if (widget.controller.isCasting) ...[
              Text(
                'Aktive Wiedergabe',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primary.withValues(alpha: 0.14),
                    child: Icon(
                      _protocolIcon(active!.protocol),
                      color: colors.primary,
                    ),
                  ),
                  title: Text(active.name),
                  subtitle: Text(
                    '${active.protocol.label} • ${widget.controller.activeMedia!.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: active.protocol == CastProtocol.airPlay
                      ? null
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: active.protocol == CastProtocol.airPlay
                      ? null
                      : () => showCastRemoteSheet(context, widget.controller),
                ),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'In der Nähe',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (_devices.isEmpty && !_scanning)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.tv_off_outlined, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        'Keine Geräte gefunden',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Smartphone und Fernseher müssen im selben lokalen Netzwerk sein. StreamFlow TV, Chromecast und DLNA werden parallel gesucht. Auf neueren Android-Versionen kann dafür eine lokale Netzwerk- oder Gerätefreigabe abgefragt werden.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.radar_rounded),
                        label: const Text('Erneut suchen'),
                      ),
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
                      child: Icon(
                        _matches(active, device)
                            ? Icons.cast_connected_rounded
                            : _protocolIcon(device.protocol),
                      ),
                    ),
                    title: Text(device.name),
                    subtitle: Text(
                      _deviceSubtitle(
                        device,
                        active: _matches(active, device),
                        preferred: _matches(preferred, device),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _matches(preferred, device)
                        ? Icon(Icons.check_circle_rounded, color: colors.primary)
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      widget.controller.setPreferredDevice(device);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${device.name} (${device.protocol.label}) als bevorzugtes Gerät gewählt.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weitere Geräte',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _CapabilityRow(
                      icon: Icons.local_fire_department_outlined,
                      title: 'Fire TV',
                      text: 'Über die StreamFlow TV Receiver App nutzbar.',
                    ),
                    if (Platform.isIOS)
                      const _CapabilityRow(
                        icon: Icons.airplay_rounded,
                        title: 'AirPlay',
                        text: 'Die Apple-Systemauswahl erscheint beim Übertragen eines Mediums.',
                      ),
                    if (Platform.isIOS)
                      const _CapabilityRow(
                        icon: Icons.connected_tv_rounded,
                        title: 'DLNA auf iPhone',
                        text: 'Direkte SSDP-Suche erfordert Apples Multicast-Networking-Freigabe; AirPlay, Cast und StreamFlow bleiben davon unabhängig.',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deviceSubtitle(
    CastDevice device, {
    required bool active,
    required bool preferred,
  }) {
    final state = active
        ? 'Aktiv verbunden'
        : preferred
            ? 'Bevorzugtes Gerät'
            : device.modelName?.trim().isNotEmpty == true
                ? device.modelName!.trim()
                : device.hasNetworkEndpoint
                    ? device.host
                    : 'Bereit';
    return '${device.protocol.label} • $state';
  }

  IconData _protocolIcon(CastProtocol protocol) => switch (protocol) {
        CastProtocol.streamFlow => Icons.tv_rounded,
        CastProtocol.googleCast => Icons.cast_rounded,
        CastProtocol.dlna => Icons.connected_tv_rounded,
        CastProtocol.airPlay => Icons.airplay_rounded,
      };
}

class _ProtocolChip extends StatelessWidget {
  const _ProtocolChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$title — ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
