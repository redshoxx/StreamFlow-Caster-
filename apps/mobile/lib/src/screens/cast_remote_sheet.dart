import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import '../cast/receiver_client.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';

Future<void> showCastRemoteSheet(
  BuildContext context,
  StreamFlowController controller,
) async {
  final device = controller.activeDevice;
  final media = controller.activeMedia;
  final pairingCode = controller.activePairingCode;
  if (device == null || media == null || pairingCode == null) return;

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.82,
      child: CastRemoteSheet(
        controller: controller,
        device: device,
        media: media,
        pairingCode: pairingCode,
      ),
    ),
  );
}

class CastRemoteSheet extends StatefulWidget {
  const CastRemoteSheet({
    super.key,
    required this.controller,
    required this.device,
    required this.media,
    required this.pairingCode,
  });

  final StreamFlowController controller;
  final CastDevice device;
  final DetectedMedia media;
  final String pairingCode;

  @override
  State<CastRemoteSheet> createState() => _CastRemoteSheetState();
}

class _CastRemoteSheetState extends State<CastRemoteSheet> {
  final _client = ReceiverClient();
  Timer? _timer;
  bool _loading = true;
  bool _connected = true;
  bool _playing = false;
  bool _refreshInFlight = false;
  bool _userSeeking = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 1.0;
  String? _error;
  String? _title;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final status = await _client.status(
        widget.device,
        pairingCode: widget.pairingCode,
      );
      if (!mounted) return;

      final receiverError = status['error']?.toString();
      setState(() {
        _loading = false;
        _connected = true;
        _playing = status['isPlaying'] == true;
        if (!_userSeeking) {
          _positionMs = (status['positionMs'] as num?)?.toInt() ?? 0;
        }
        _durationMs = (status['durationMs'] as num?)?.toInt() ?? 0;
        _volume = ((status['volume'] as num?)?.toDouble() ?? _volume)
            .clamp(0.0, 1.0)
            .toDouble();
        _title = status['title']?.toString();
        _error = receiverError == null || receiverError.isEmpty
            ? null
            : 'Wiedergabefehler: $receiverError';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _connected = false;
        if (!silent) {
          _error = 'Der Fernseher ist derzeit nicht erreichbar.';
        }
      });
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<bool> _run(Future<void> Function() command) async {
    try {
      if (mounted) setState(() => _error = null);
      await command();
      await _refresh();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _connected = false;
          _error = 'Befehl konnte nicht an den Fernseher gesendet werden.';
        });
      }
      return false;
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final target = (_positionMs + seconds * 1000)
        .clamp(0, _durationMs > 0 ? _durationMs : 1 << 31)
        .toInt();
    await _run(
      () => _client.seek(
        widget.device,
        Duration(milliseconds: target),
        pairingCode: widget.pairingCode,
      ),
    );
  }

  Future<void> _stop() async {
    final stopped = await _run(
      () => _client.stop(
        widget.device,
        pairingCode: widget.pairingCode,
      ),
    );
    if (!stopped) return;

    widget.controller.endCasting();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = _durationMs > 0 ? _durationMs : 1;
    final sliderPosition = math.min(_positionMs, duration).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.cast_connected, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.device.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _connected ? 'Verbunden' : 'Verbindung unterbrochen',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _connected ? colors.primary : colors.error,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _refreshInFlight ? null : () => _refresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Container(
            height: 154,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primaryContainer, colors.secondaryContainer],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 72,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _title?.trim().isNotEmpty == true ? _title! : widget.media.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            widget.media.url.host,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
          ],
          const SizedBox(height: 22),
          Slider(
            value: sliderPosition,
            max: duration.toDouble(),
            onChangeStart: _durationMs <= 0
                ? null
                : (_) => setState(() => _userSeeking = true),
            onChanged: _durationMs <= 0
                ? null
                : (value) => setState(() => _positionMs = value.toInt()),
            onChangeEnd: _durationMs <= 0
                ? null
                : (value) async {
                    setState(() => _userSeeking = false);
                    await _run(
                      () => _client.seek(
                        widget.device,
                        Duration(milliseconds: value.toInt()),
                        pairingCode: widget.pairingCode,
                      ),
                    );
                  },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_format(_positionMs), style: theme.textTheme.bodySmall),
                Text(
                  _durationMs > 0 ? _format(_durationMs) : '--:--',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _connected ? () => _seekRelative(-10) : null,
                iconSize: 34,
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 18),
              FilledButton(
                onPressed: _connected
                    ? () => _run(
                          () => _playing
                              ? _client.pause(
                                  widget.device,
                                  pairingCode: widget.pairingCode,
                                )
                              : _client.play(
                                  widget.device,
                                  pairingCode: widget.pairingCode,
                                ),
                        )
                    : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 38,
                ),
              ),
              const SizedBox(width: 18),
              IconButton(
                onPressed: _connected ? () => _seekRelative(10) : null,
                iconSize: 34,
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: _connected
                      ? (value) => setState(() => _volume = value)
                      : null,
                  onChangeEnd: _connected
                      ? (value) => _run(
                            () => _client.setVolume(
                              widget.device,
                              value,
                              pairingCode: widget.pairingCode,
                            ),
                          )
                      : null,
                ),
              ),
              const Icon(Icons.volume_up_rounded),
            ],
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _connected
                ? _stop
                : () {
                    widget.controller.endCasting();
                    Navigator.of(context).pop();
                  },
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(_connected ? 'Übertragung stoppen' : 'Sitzung entfernen'),
          ),
        ],
      ),
    );
  }

  String _format(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
