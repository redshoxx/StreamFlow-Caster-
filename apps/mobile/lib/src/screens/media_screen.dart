import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/streamflow_controller.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import 'cast_media_dialog.dart';
import 'cast_remote_sheet.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key, required this.controller});

  final StreamFlowController controller;

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  MediaKind? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.controller.detectedMedia;
    final visible = _filter == null ? all : all.where((item) => item.kind == _filter).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Medien', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${all.length} erkannte Quellen', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Liste leeren',
                onPressed: all.isEmpty ? null : widget.controller.clearDetectedMedia,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'Alle', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                _FilterChip(label: 'Video', selected: _filter == MediaKind.video, onTap: () => setState(() => _filter = MediaKind.video)),
                _FilterChip(label: 'HLS', selected: _filter == MediaKind.hls, onTap: () => setState(() => _filter = MediaKind.hls)),
                _FilterChip(label: 'DASH', selected: _filter == MediaKind.dash, onTap: () => setState(() => _filter = MediaKind.dash)),
                _FilterChip(label: 'Audio', selected: _filter == MediaKind.audio, onTap: () => setState(() => _filter = MediaKind.audio)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Icon(Icons.video_search_outlined, size: 46),
                    const SizedBox(height: 12),
                    Text('Noch keine Medien erkannt', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('Öffne im Browser eine Seite mit einem unterstützten Video-, HLS- oder Audio-Stream.', textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else
            for (final item in visible) ...[
              _MediaCard(
                item: item,
                onCast: () => _cast(item),
                onCopy: () async {
                  await Clipboard.setData(ClipboardData(text: item.url.toString()));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medien-URL kopiert.')));
                },
                onRemove: () => widget.controller.removeDetectedMedia(item),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Future<void> _cast(DetectedMedia item) async {
    final device = await showDialog<CastDevice>(
      context: context,
      builder: (_) => CastMediaDialog(
        media: item,
        preferredDeviceId: widget.controller.preferredDevice?.id,
      ),
    );
    if (!mounted || device == null) return;
    widget.controller.startCasting(device, item);
    await showCastRemoteSheet(context, widget.controller);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.onCast, required this.onCopy, required this.onRemove});

  final DetectedMedia item;
  final VoidCallback onCast;
  final VoidCallback onCopy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Icon(_icon(item.kind), color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('${_label(item.kind)} • ${item.url.host}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(onPressed: onCast, tooltip: 'Abspielen', icon: const Icon(Icons.cast_outlined)),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'copy') onCopy();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('URL kopieren')),
                PopupMenuItem(value: 'remove', child: Text('Entfernen')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(MediaKind kind) => switch (kind) {
        MediaKind.audio => Icons.music_note_rounded,
        MediaKind.hls => Icons.stream_rounded,
        MediaKind.dash => Icons.hub_outlined,
        MediaKind.video => Icons.movie_outlined,
        MediaKind.unknown => Icons.insert_drive_file_outlined,
      };

  String _label(MediaKind kind) => switch (kind) {
        MediaKind.hls => 'HLS',
        MediaKind.dash => 'DASH',
        MediaKind.video => 'Video',
        MediaKind.audio => 'Audio',
        MediaKind.unknown => 'Medium',
      };
}
