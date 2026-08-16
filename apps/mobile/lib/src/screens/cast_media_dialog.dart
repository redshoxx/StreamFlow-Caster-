import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cast/device_discovery_service.dart';
import '../cast/dlna_cast_service.dart';
import '../cast/google_cast_service.dart';
import '../cast/receiver_client.dart';
import '../cast/web_receiver_server.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import '../storage/receiver_credential_store.dart';

class CastMediaDialog extends StatefulWidget {
  const CastMediaDialog({
    super.key,
    this.media,
    this.preferredDeviceId,
  });

  final DetectedMedia? media;
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

  bool get _selectionOnly => widget.media == null;

  @override
  void initState() {
    super.initState();
    _subscription = _discovery.devices.listen((devices) {
      final sorted = [...devices];
      final preferred = widget.preferredDeviceId;
      sorted.sort((a, b) {
        if (preferred != null) {
          if (a.id == preferred && b.id != preferred) return -1;
          if (b.id == preferred && a.id != preferred) return 1;
        }
        final aFire = _isFireTv(a);
        final bFire = _isFireTv(b);
        if (aFire != bFire) return aFire ? -1 : 1;
        final protocol = a.protocol.index.compareTo(b.protocol.index);
        return protocol != 0 ? protocol : a.name.compareTo(b.name);
      });
      if (mounted) setState(() => _devices = sorted);
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _scanning = true;
        _error = null;
      });
    }
    try {
      await _discovery.start();
    } catch (_) {
      if (mounted && _devices.isEmpty) {
        setState(() {
          _error =
              'Die Gerätesuche konnte nicht vollständig gestartet werden. Prüfe, ob lokales Netzwerk/WLAN für StreamFlow erlaubt ist.';
        });
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
      final media = widget.media;
      switch (device.protocol) {
        case CastProtocol.streamFlow:
          await _castStreamFlow(device);
          break;
        case CastProtocol.googleCast:
          if (media != null) {
            await GoogleCastService.instance.load(device, media);
          }
          if (mounted) Navigator.of(context).pop(CastTarget(device: device));
          break;
        case CastProtocol.dlna:
          if (media != null) {
            await DlnaCastService.instance.load(device, media);
          }
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
          _error = _selectionOnly
              ? '${device.name} konnte nicht verbunden werden.'
              : '${device.name} konnte den Stream nicht laden.';
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

    final media = widget.media;
    if (media != null) {
      await _client.load(
        device,
        media.url,
        title: media.displayName,
        pairingCode: pairingCode,
      );
    }
    if (mounted) {
      Navigator.of(context).pop(
        CastTarget(device: device, pairingCode: pairingCode),
      );
    }
  }

  Future<void> _openWebReceiver() async {
    if (_connectingId != null) return;
    setState(() {
      _connectingId = 'web-browser-receiver';
      _error = null;
    });

    try {
      final session = await WebReceiverServer.instance.start();
      if (!mounted) return;

      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.language_rounded),
          title: const Text('Webbrowser-Empfänger'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Öffne auf dem Fernseher einen Webbrowser und rufe diese Adresse auf. Smartphone und TV müssen im selben Netzwerk sein.',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    session.receiverUrl.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: session.receiverUrl.toString()),
                    );
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Empfänger-Adresse kopiert.')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Adresse kopieren'),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectionOnly
                      ? 'Sobald auf dem TV „StreamFlow Web Receiver – Bereit“ angezeigt wird, tippe unten auf „Verbinden“.'
                      : 'Sobald auf dem TV „StreamFlow Web Receiver – Bereit“ angezeigt wird, tippe unten auf „Übertragen“.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: Icon(_selectionOnly ? Icons.link_rounded : Icons.cast_rounded),
              label: Text(_selectionOnly ? 'Verbinden' : 'Übertragen'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (proceed != true) {
        setState(() => _connectingId = null);
        return;
      }

      final media = widget.media;
      if (media != null) {
        await _client.load(
          session.device,
          media.url,
          title: media.displayName,
          pairingCode: session.pairingCode,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(
          CastTarget(
            device: session.device,
            pairingCode: session.pairingCode,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connectingId = null;
        _error =
            'Der Webbrowser-Empfänger konnte nicht gestartet werden. Prüfe WLAN und lokale Netzwerkberechtigungen.';
      });
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
          setState(() => _error =
              'Kopplungscode falsch. Prüfe den Code am Fernseher.');
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
                    if (value.length == 8) {
                      Navigator.of(dialogContext).pop(value);
                    }
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

  Future<void> _showReceiverHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.tv_rounded),
        title: const Text('StreamFlow TV Empfänger'),
        content: const Text(
          'Installiere und öffne die StreamFlow TV Receiver-App auf Fire TV, Android TV oder Google TV. Sobald der Receiver geöffnet ist und sich im selben Netzwerk befindet, erscheint er automatisch oben in der Geräteliste.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final airPlayDevice = const CastDevice(
      id: 'airplay-system-picker',
      name: 'AirPlay auf Apple TV',
      protocol: CastProtocol.airPlay,
      modelName: 'Apple-Systemauswahl',
    );

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Schließen',
            onPressed: _connectingId == null
                ? () => Navigator.of(context).pop()
                : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: Text(
            _selectionOnly ? 'Mit TV verbinden' : 'Gerät zum Übertragen wählen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Neu suchen',
              onPressed: _connectingId == null && !_scanning ? _start : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                color: colors.errorContainer,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: colors.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            if (_scanning) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                children: [
                  if (widget.media case final media?) ...[
                    Text(
                      media.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    Text(
                      'Wähle den Fernseher jetzt aus. Sobald StreamFlow danach eine Videoquelle erkennt, kann sie direkt auf dieses Gerät übertragen werden.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_devices.isNotEmpty) ...[
                    Text(
                      'In deinem Netzwerk',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._devices.map(_deviceTile),
                    const SizedBox(height: 20),
                  ] else if (!_scanning) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.wifi_find_rounded),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Noch kein kompatibles Gerät gefunden. Lass den TV-Empfänger geöffnet und prüfe, ob Smartphone und TV im selben WLAN/LAN sind.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    'Weitere Empfänger',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _actionTile(
                    icon: Icons.local_fire_department_outlined,
                    title: 'Fire TV / Android TV',
                    subtitle:
                        'Über die StreamFlow TV Receiver-App. Danach erscheint das Gerät automatisch oben.',
                    onTap: _showReceiverHelp,
                  ),
                  _actionTile(
                    icon: Icons.language_rounded,
                    title: 'Webbrowser-Empfänger',
                    subtitle:
                        'Direkt über den Webbrowser des Fernsehers übertragen – ohne zusätzliche TV-App.',
                    onTap: _openWebReceiver,
                    loading: _connectingId == 'web-browser-receiver',
                  ),
                  if (Platform.isIOS) _deviceTile(airPlayDevice),
                  const SizedBox(height: 22),
                  Text(
                    'StreamFlow erkennt StreamFlow TV/Fire TV Receiver, Google Cast und kompatible DLNA/UPnP-Geräte automatisch. AirPlay nutzt auf dem iPhone die Apple-Systemauswahl.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(CastDevice device) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final preferred = device.id == widget.preferredDeviceId;
    final endpoint = device.host.trim().isNotEmpty ? device.host.trim() : null;
    final subtitleParts = <String>[
      if (preferred) 'Bevorzugtes Gerät' else device.protocol.label,
      if (device.modelName?.trim().isNotEmpty == true) device.modelName!.trim(),
      if (endpoint != null) endpoint,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _isFireTv(device)
                ? colors.tertiaryContainer
                : colors.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _protocolIcon(device),
            color: _isFireTv(device)
                ? colors.onTertiaryContainer
                : colors.onPrimaryContainer,
          ),
        ),
        title: Text(
          device.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitleParts.join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _connectingId == device.id
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        enabled: _connectingId == null,
        onTap: () => _cast(device),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
    bool loading = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        enabled: _connectingId == null,
        onTap: () => unawaited(onTap()),
      ),
    );
  }

  bool _isFireTv(CastDevice device) {
    final text = '${device.name} ${device.modelName ?? ''}'.toLowerCase();
    return text.contains('fire tv') ||
        RegExp(r'(^|[^a-z])aft[a-z0-9]*', caseSensitive: false).hasMatch(text);
  }

  IconData _protocolIcon(CastDevice device) {
    if (_isFireTv(device)) return Icons.local_fire_department_rounded;
    return switch (device.protocol) {
      CastProtocol.streamFlow => Icons.tv_rounded,
      CastProtocol.googleCast => Icons.cast_rounded,
      CastProtocol.dlna => Icons.connected_tv_rounded,
      CastProtocol.airPlay => Icons.airplay_rounded,
    };
  }
}
