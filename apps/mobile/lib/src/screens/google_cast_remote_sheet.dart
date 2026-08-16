import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../app/streamflow_controller.dart';
import '../cast/google_cast_service.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';

class GoogleCastRemoteSheet extends StatefulWidget {
  const GoogleCastRemoteSheet({
    super.key,
    required this.controller,
    required this.device,
    required this.media,
  });

  final StreamFlowController controller;
  final CastDevice device;
  final DetectedMedia media;

  @override
  State<GoogleCastRemoteSheet> createState() => _GoogleCastRemoteSheetState();
}

class _GoogleCastRemoteSheetState extends State<GoogleCastRemoteSheet> {
  final _service = GoogleCastService.instance;
  StreamSubscription<GoggleCastMediaStatus?>? _subscription;
  Timer? _positionTimer;
  GoggleCastMediaStatus? _status;
  Duration _position = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = _service.mediaStatus;
    _position = _service.playerPosition;
    _subscription = _service.mediaStatusStream.listen(
      (status) {
        if (mounted) setState(() => _status = status);
      },
      onError: (_) {
        if (mounted) setState(() => _error = 'Cast-Status konnte nicht gelesen werden.');
      },
    );
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _position = _service.playerPosition);
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      setState(() => _error = null);
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = 'Chromecast-Befehl konnte nicht ausgeführt werden.');
    }
  }

  Future<void> _stop() async {
    await _run(_service.stop);
    widget.controller.endCasting();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = _status;
    final duration = status?.mediaInformation?.duration ?? Duration.zero;
    final playing = status?.playerState == CastMediaPlayerState.playing;
    final maxMs = math.max(duration.inMilliseconds, 1);
    final positionMs = _position.inMilliseconds.clamp(0, maxMs);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const SizedBox(height: 24),
          Container(
            height: 150,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primaryContainer, colors.secondaryContainer],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Icon(Icons.cast_connected_rounded, size: 68, color: colors.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.media.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            'Google Cast • ${widget.device.name}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: 18),
          Slider(
            value: positionMs.toDouble(),
            max: maxMs.toDouble(),
            onChanged: duration == Duration.zero
                ? null
                : (value) => setState(() => _position = Duration(milliseconds: value.round())),
            onChangeEnd: duration == Duration.zero
                ? null
                : (value) => _run(() => _service.seek(Duration(milliseconds: value.round()))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_format(_position), style: theme.textTheme.bodySmall),
                Text(duration == Duration.zero ? '--:--' : _format(duration), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 34,
                onPressed: () => _run(() => _service.seek(_relative(-10, duration))),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 18),
              FilledButton(
                onPressed: () => _run(playing ? _service.pause : _service.play),
                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(20)),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 38),
              ),
              const SizedBox(width: 18),
              IconButton(
                iconSize: 34,
                onPressed: () => _run(() => _service.seek(_relative(10, duration))),
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Lautstärke'),
              const SizedBox(width: 12),
              GoogleCastVolume(
                iconColor: colors.primary,
                sliderActiveColor: colors.primary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Übertragung stoppen'),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.cast_rounded, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.device.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text('Google Cast verbunden'),
            ],
          ),
        ),
      ],
    );
  }

  Duration _relative(int seconds, Duration duration) {
    final upper = duration == Duration.zero ? const Duration(days: 30) : duration;
    final target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) return Duration.zero;
    if (target > upper) return upper;
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
