import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import '../cast/dlna_cast_service.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';

class DlnaRemoteSheet extends StatefulWidget {
  const DlnaRemoteSheet({
    super.key,
    required this.controller,
    required this.device,
    required this.media,
  });

  final StreamFlowController controller;
  final CastDevice device;
  final DetectedMedia media;

  @override
  State<DlnaRemoteSheet> createState() => _DlnaRemoteSheetState();
}

class _DlnaRemoteSheetState extends State<DlnaRemoteSheet> {
  final _service = DlnaCastService.instance;
  Timer? _timer;
  bool _refreshInFlight = false;
  bool _connected = true;
  bool _playing = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_refresh(silent: true)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final status = await _service.status(widget.device);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _playing = status.playing;
        _position = status.position;
        _duration = status.duration;
        _volume = status.volume;
        if (!silent) _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _connected = false;
          if (!silent) _error = 'DLNA-Fernseher ist derzeit nicht erreichbar.';
        });
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    try {
      if (mounted) setState(() => _error = null);
      await action();
      await _refresh();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _connected = false;
          _error = 'DLNA-Befehl konnte nicht ausgeführt werden.';
        });
      }
      return false;
    }
  }

  Future<void> _stop() async {
    final stopped = await _run(() => _service.stop(widget.device));
    if (!stopped) return;
    widget.controller.endCasting();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxMs = math.max(_duration.inMilliseconds, 1);
    final positionMs = _position.inMilliseconds.clamp(0, maxMs);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.connected_tv_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.device.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(_connected ? 'DLNA / UPnP verbunden' : 'Verbindung unterbrochen'),
                  ],
                ),
              ),
              IconButton(onPressed: _refreshInFlight ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 150,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [colors.primaryContainer, colors.secondaryContainer]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Icon(Icons.play_circle_fill_rounded, size: 70, color: colors.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.media.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: 16),
          Slider(
            value: positionMs.toDouble(),
            max: maxMs.toDouble(),
            onChanged: _duration == Duration.zero
                ? null
                : (value) => setState(() => _position = Duration(milliseconds: value.round())),
            onChangeEnd: _duration == Duration.zero
                ? null
                : (value) => _run(() => _service.seek(widget.device, Duration(milliseconds: value.round()))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_format(_position), style: theme.textTheme.bodySmall),
                Text(_duration == Duration.zero ? '--:--' : _format(_duration), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 34,
                onPressed: _connected ? () => _run(() => _service.seek(widget.device, _relative(-10))) : null,
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 18),
              FilledButton(
                onPressed: _connected
                    ? () => _run(() => _playing ? _service.pause(widget.device) : _service.play(widget.device))
                    : null,
                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(20)),
                child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 38),
              ),
              const SizedBox(width: 18),
              IconButton(
                iconSize: 34,
                onPressed: _connected ? () => _run(() => _service.seek(widget.device, _relative(10))) : null,
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: _connected ? (value) => setState(() => _volume = value) : null,
                  onChangeEnd: _connected ? (value) => _run(() => _service.setVolume(widget.device, value)) : null,
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

  Duration _relative(int seconds) {
    final target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) return Duration.zero;
    if (_duration != Duration.zero && target > _duration) return _duration;
    return target;
  }

  String _format(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
