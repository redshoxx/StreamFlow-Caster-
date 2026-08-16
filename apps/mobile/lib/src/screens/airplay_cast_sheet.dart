import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_to_airplay/flutter_to_airplay.dart';

import '../models/detected_media.dart';

Future<void> showAirPlayCastSheet(
  BuildContext context,
  DetectedMedia media,
) async {
  if (!Platform.isIOS) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.78,
      child: _AirPlayCastSheet(media: media),
    ),
  );
}

class _AirPlayCastSheet extends StatelessWidget {
  const _AirPlayCastSheet({required this.media});

  final DetectedMedia media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.airplay_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AirPlay',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Apple TV oder AirPlay-fähigen Fernseher auswählen',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: ColoredBox(
                color: Colors.black,
                child: FlutterAVPlayerView(
                  urlString: media.url.toString(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            media.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'AirPlay-Gerät wählen',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AirPlayRoutePickerView(
                  prioritizesVideoDevices: true,
                  tintColor: colors.primary,
                  activeTintColor: colors.primary,
                  backgroundColor: Colors.transparent,
                  width: 50,
                  height: 50,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Die Geräteauswahl wird von iOS bereitgestellt. Wiedergabe und AirPlay laufen über Apples AVPlayer.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
