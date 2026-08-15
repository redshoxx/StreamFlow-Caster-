import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import '../cast/local_media_server.dart';
import '../media/media_detector.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import 'cast_media_dialog.dart';
import 'cast_remote_sheet.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.controller});

  final StreamFlowController controller;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _server = LocalMediaServer();
  PlatformFile? _selected;
  bool _preparing = false;
  String? _error;

  Future<void> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const [
        'mp4', 'm4v', 'mov', 'webm', 'mkv', 'ts',
        'mp3', 'aac', 'm4a', 'flac', 'ogg', 'wav',
      ],
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    await _server.stop();
    if (!mounted) return;
    setState(() {
      _selected = result.files.first;
      _error = null;
    });
  }

  Future<void> _cast() async {
    final selected = _selected;
    final path = selected?.path;
    if (selected == null || path == null) {
      setState(() => _error = 'Die ausgewählte Datei besitzt keinen lesbaren lokalen Pfad.');
      return;
    }

    setState(() {
      _preparing = true;
      _error = null;
    });

    try {
      final uri = await _server.serve(File(path), fileName: selected.name);
      final media = MediaDetector.fromUrl(uri.toString(), label: selected.name) ??
          DetectedMedia(url: uri, kind: MediaKind.video, label: selected.name);

      if (!mounted) return;
      final device = await showDialog<CastDevice>(
        context: context,
        builder: (_) => CastMediaDialog(
          media: media,
          preferredDeviceId: widget.controller.preferredDevice?.id,
        ),
      );

      if (!mounted) return;
      if (device == null) {
        await _server.stop();
        return;
      }

      widget.controller.startCasting(
        device,
        media,
        onEnd: () => unawaited(_server.stop()),
      );
      await showCastRemoteSheet(context, widget.controller);
    } on LocalMediaServerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Die lokale Datei konnte nicht für den Fernseher bereitgestellt werden.');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  void dispose() {
    unawaited(_server.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text('Lokale Dateien', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Video oder Audio vom Smartphone direkt im lokalen Netzwerk an StreamFlow TV senden.'),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.folder_open_rounded, size: 34, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    selected?.name ?? 'Datei auswählen',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 4),
                    Text(_formatBytes(selected.size), style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _preparing ? null : _pick,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(selected == null ? 'Datei auswählen' : 'Andere Datei wählen'),
                    ),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _preparing ? null : _cast,
                        icon: _preparing
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cast_rounded),
                        label: Text(_preparing ? 'Wird vorbereitet …' : 'Auf Fernseher abspielen'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: colors.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Card(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.wifi_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Die Datei bleibt auf deinem Gerät. StreamFlow stellt sie nur während der Wiedergabe über eine zufällige, temporäre lokale URL bereit. Byte-Range-Seeking wird unterstützt.'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
