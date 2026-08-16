import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cast/device_discovery_service.dart';
import '../cast/dlna_cast_service.dart';
import '../cast/google_cast_service.dart';
import '../cast/receiver_client.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import '../storage/receiver_credential_store.dart';

class CastMediaDialog extends StatefulWidget {
  const CastMediaDialog({
    super.key,
    required this.media,
    this.preferredDeviceId,
  });

  final DetectedMedia media;
  final String? preferredDeviceId;

  @override
  State<CastMediaDialog> createState() => _CastMediaDialogState();
}

class _CastMediaDialogState extends State<CastMediaDialog> {
  final _discovery = DeviceDiscoveryService();
  final _client = ReceiverClient();
  final _credentials = ReceiverCredentialStore();
  StreamSubscription<List<CastDevice>>? _subscription;
  List<CastDevice> _devices = const [];
  String? _error;
  String? _connectingId;
  var _scanning = true;

  @override
  void initState() {
    super.initState();
    _subscription = _discovery.devices.listen((devices) {
      final sorted = [...devices];
      final preferred = widget.preferredDeviceId;
      if (preferred != null) {
        sorted.sort((a, b) {
          if (a.id == preferred && b.id != preferred) return -1;
          if (b.id == preferred && a.id != preferred) return 1;
          final protocol = a.protocol.index.compareTo(b.protocol.index);
          return protocol != 0 ? protocol : a.name.compareTo(b.name);
        });
      }
      if (mounted) setState(() => _devices = sorted);
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _discovery.start();
    } catch (_) {
      if (mounted && _devices.isEmpty) {
        setState(() => _error = 'Gerätesuche konnte nicht vollständig gestartet werden.');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _cast(CastDevice device) async {
    if (_connectingId != null) return;
    setState(() {
      _connectingId = device.id;
      _error = null;
    });

    try {
      switch (device.protocol) {
        case CastProtocol.streamFlow:
          await _castStreamFlow(device);
          break;
        case CastProtocol.googleCast:
          await GoogleCastService.instance.load(device, widget.media);
          if (mounted) Navigator.of(context).pop(CastTarget(device: device));
          break;
        case CastProtocol.dlna:
          await DlnaCastService.instance.load(device, widget.media);
          if (mounted) Navigator.of(context).pop(CastTarget(device: device));
          break;
        case CastProtocol.airPlay:
          if (mounted) Navigator.of(context).pop(CastTarget(device: device));
          break;
      }
    } on ReceiverException catch (error) {
      if (!mounted) return;
      setState(() {
        _connectingId = null;
        _error = error.isPairingRequired
            ? 'Der Kopplungscode ist nicht mehr gültig. Bitte erneut verbinden.'
            : 'Der StreamFlow Receiver antwortet nicht mit dem aktuellen Protokoll.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectingId = null;
          _error = '${device.name} konnte den Stream nicht laden.';
        });
      }
    }
  }

  Future<void> _castStreamFlow(CastDevice device) async {
    final health = await _client.health(device);
    if (health['protocol'] != 2 || health['pairingRequired'] != true) {
      throw const ReceiverException('Unsupported receiver protocol.');
    }

    final pairingCode = await _resolvePairingCode(device);
    if (!mounted) return;
    if (pairingCode == null) {
      setState(() => _connectingId = null);
      return;
    }

    await _client.load(
      device,
      widget.media.url,
      title: widget.media.displayName,
      pairingCode: pairingCode,
    );
    if (mounted) {
      Navigator.of(context).pop(
        CastTarget(device: device, pairingCode: pairingCode),
      );
    }
  }

  Future<String?> _resolvePairingCode(CastDevice device) async {
    final saved = await _credentials.load(device.id);
    if (saved != null) {
      try {
        await _client.status(device, pairingCode: saved);
        return saved;
      } on ReceiverException catch (error) {
        if (!error.isPairingRequired) rethrow;
        await _credentials.remove(device.id);
      }
    }

    for (var attempt = 0; attempt < 2; attempt += 1) {
      if (!mounted) return null;
      final entered = await _showPairingDialog(device);
      if (entered == null) return null;

      try {
        await _client.status(device, pairingCode: entered);
        await _credentials.save(device.id, entered);
        return entered;
      } on ReceiverException catch (error) {
        if (!error.isPairingRequired) rethrow;
        if (mounted) {
          setState(() => _error = 'Kopplungscode falsch. Prüfe den Code am Fernseher.');
        }
      }
    }
    return null;
  }

  Future<String?> _showPairingDialog(CastDevice device) async {
    final input = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            icon: const Icon(Icons.lock_outline_rounded),
            title: const Text('Fernseher koppeln'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gib den 8-stelligen Code ein, der auf ${device.name} angezeigt wird.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: input,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (value) {
                    if (value.length == 8) Navigator.of(dialogContext).pop(value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Kopplungscode',
                    hintText: '12345678',
                    counterText: '',
                  ),
                  maxLength: 8,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: input.text.length == 8
                    ? () => Navigator.of(dialogContext).pop(input.text)
                    : null,
                child: const Text('Koppeln'),
              ),
            ],
          ),
        ),
      );
    } finally {
      input.dispose();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_discovery.dispose());
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final airPlayDevice = const CastDevice(
      id: 'airplay-system-picker',
      name: 'AirPlay',
      protocol: CastProtocol.airPlay,
      modelName: 'Apple Systemauswahl',
    );

    return AlertDialog(
      icon: const Icon(Icons.cast_rounded),
      title: const Text('Auf Gerät abspielen'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.media.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (Platform.isIOS) _deviceTile(airPlayDevice),
                  ..._devices.map(_deviceTile),
                  if (_devices.isEmpty && !Platform.isIOS && !_scanning)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Keine kompatiblen Geräte gefunden. Prüfe, ob Smartphone und Fernseher im selben Netzwerk sind.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'StreamFlow erkennt Receiver, Chromecast/Google Cast und DLNA automatisch. AirPlay nutzt auf dem iPhone die Apple-Systemauswahl.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _connectingId == null ? () => Navigator.of(context).pop() : null,
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }

  Widget _deviceTile(CastDevice device) {
    final preferred = device.id == widget.preferredDeviceId;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_protocolIcon(device.protocol))),
        title: Text(device.name),
        subtitle: Text(
          preferred
              ? '${device.protocol.label} • Bevorzugtes Gerät'
              : device.modelName?.trim().isNotEmpty == true
                  ? '${device.protocol.label} • ${device.modelName}'
                  : device.protocol.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _connectingId == device.id
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow_rounded),
        enabled: _connectingId == null,
        onTap: () => _cast(device),
      ),
    );
  }

  IconData _protocolIcon(CastProtocol protocol) => switch (protocol) {
        CastProtocol.streamFlow => Icons.tv_rounded,
        CastProtocol.googleCast => Icons.cast_rounded,
        CastProtocol.dlna => Icons.connected_tv_rounded,
        CastProtocol.airPlay => Icons.airplay_rounded,
      };
}
