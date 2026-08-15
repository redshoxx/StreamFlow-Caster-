import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/streamflow_controller.dart';
import '../browser/ad_blocker.dart';
import '../media/media_detector.dart';
import '../models/browser_entry.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import 'cast_media_dialog.dart';
import 'cast_remote_sheet.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.controller});

  final StreamFlowController controller;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _web;
  final _address = TextEditingController(text: 'https://www.google.com');
  final List<DetectedMedia> _pageMedia = <DetectedMedia>[];
  final _adBlocker = AdBlocker();

  var _progress = 0;
  var _pageTitle = 'Browser';
  var _adBlockEnabled = true;
  var _blockedAds = 0;
  Uri? _currentUri;

  @override
  void initState() {
    super.initState();
    _currentUri = Uri.parse(_address.text);
    unawaited(_restoreAdBlocker());

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'StreamFlowAdBlock',
        onMessageReceived: (message) {
          if (!mounted || !_adBlockEnabled) return;
          final delta = int.tryParse(message.message) ?? 0;
          if (delta <= 0) return;
          setState(() => _blockedAds += delta);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _address.text = url;
              _currentUri = Uri.tryParse(url);
              _progress = 0;
              _blockedAds = 0;
              _pageMedia.clear();
            });

            if (_adBlockEnabled) {
              Future<void>.delayed(const Duration(milliseconds: 150), () async {
                if (mounted && _adBlockEnabled) await _applyAdBlocker();
              });
              Future<void>.delayed(const Duration(milliseconds: 700), () async {
                if (mounted && _adBlockEnabled) await _applyAdBlocker();
              });
            }
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            _address.text = url;
            if (_adBlockEnabled) await _applyAdBlocker();

            final title = await _web.getTitle();
            if (!mounted) return;

            final resolvedTitle = title?.trim().isNotEmpty == true
                ? title!.trim()
                : Uri.tryParse(url)?.host ?? 'Browser';
            final uri = Uri.tryParse(url);
            setState(() {
              _pageTitle = resolvedTitle;
              _currentUri = uri;
              _progress = 100;
            });
            if (uri != null) {
              unawaited(widget.controller.recordVisit(uri, resolvedTitle));
            }

            await _scan();
            Future<void>.delayed(const Duration(seconds: 2), () async {
              if (!mounted) return;
              if (_adBlockEnabled) await _applyAdBlocker();
              await _scan();
            });
          },
          onNavigationRequest: (request) {
            if (_adBlockEnabled && _adBlocker.shouldBlockUrl(request.url)) {
              if (mounted) setState(() => _blockedAds += 1);
              return NavigationDecision.prevent;
            }
            _capture(request.url);
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_address.text));
  }

  Future<void> _restoreAdBlocker() async {
    try {
      final enabled = await _adBlocker.loadEnabled();
      if (!mounted) return;
      if (enabled != _adBlockEnabled) setState(() => _adBlockEnabled = enabled);
      if (enabled) await _applyAdBlocker();
    } catch (_) {
      // Ad blocking stays enabled by default if preferences cannot be read.
    }
  }

  Future<void> _applyAdBlocker() async {
    if (!_adBlockEnabled) return;
    try {
      await _web.runJavaScript(_adBlocker.javaScript);
    } catch (_) {
      // Some documents do not allow script execution during early load stages.
    }
  }

  Future<void> _toggleAdBlocker() async {
    final enabled = !_adBlockEnabled;
    setState(() {
      _adBlockEnabled = enabled;
      _blockedAds = 0;
    });

    try {
      await _adBlocker.saveEnabled(enabled);
    } catch (_) {}

    if (enabled) {
      await _applyAdBlocker();
    } else {
      await _web.reload();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enabled ? 'Adblocker aktiviert.' : 'Adblocker deaktiviert.')),
    );
  }

  Future<void> _scan() async {
    try {
      final raw = await _web.runJavaScriptReturningResult(MediaDetector.domScannerScript);
      String json = raw.toString();
      if (json.startsWith('"') && json.endsWith('"')) {
        json = jsonDecode(json) as String;
      }
      final decoded = jsonDecode(json);
      if (decoded is! List) return;
      for (final item in decoded.whereType<Map>()) {
        _capture(
          item['url']?.toString() ?? '',
          label: item['label']?.toString(),
          mime: item['type']?.toString(),
        );
      }
    } catch (_) {
      // Some pages block injected JavaScript. Navigation interception still works.
    }
  }

  void _capture(String url, {String? label, String? mime}) {
    if (_adBlockEnabled && _adBlocker.shouldBlockUrl(url)) return;
    final candidate = MediaDetector.fromUrl(url, label: label, mime: mime);
    if (candidate == null || _pageMedia.contains(candidate)) return;
    if (mounted) setState(() => _pageMedia.add(candidate));
    widget.controller.addDetectedMedia(candidate);
  }

  void _go() {
    var value = _address.text.trim();
    if (!value.contains('://')) {
      if (value.contains('.') && !value.contains(' ')) {
        value = 'https://$value';
      } else {
        value = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}';
      }
    }
    final uri = Uri.tryParse(value);
    if (uri != null) {
      FocusScope.of(context).unfocus();
      _web.loadRequest(uri);
    }
  }

  Future<void> _home() => _web.loadRequest(Uri.parse('https://www.google.com'));

  Future<void> _toggleFavorite() async {
    final uri = _currentUri;
    if (uri == null) return;
    final wasFavorite = widget.controller.isFavorite(uri);
    await widget.controller.toggleFavorite(uri, _pageTitle);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(wasFavorite ? 'Aus Favoriten entfernt.' : 'Zu Favoriten hinzugefügt.')),
    );
  }

  void _openBrowserEntry(BrowserEntry entry) {
    Navigator.of(context).pop();
    _web.loadRequest(entry.url);
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final favorite = widget.controller.isFavorite(_currentUri);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('StreamFlow', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: favorite ? 'Favorit entfernen' : 'Favorit hinzufügen',
                  onPressed: _currentUri == null ? null : _toggleFavorite,
                  icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded),
                ),
                IconButton(
                  tooltip: 'Favoriten und Verlauf',
                  onPressed: () => _showLibrary(context),
                  icon: const Icon(Icons.bookmarks_outlined),
                ),
                IconButton(
                  tooltip: _adBlockEnabled
                      ? 'Adblocker aktiv • $_blockedAds blockiert'
                      : 'Adblocker deaktiviert',
                  onPressed: _toggleAdBlocker,
                  icon: Badge(
                    isLabelVisible: _adBlockEnabled && _blockedAds > 0,
                    label: Text(_blockedAds > 99 ? '99+' : '$_blockedAds'),
                    child: Icon(
                      Icons.security,
                      color: _adBlockEnabled ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.controller.isCasting)
                  IconButton(
                    tooltip: 'Wiedergabe steuern',
                    onPressed: () => showCastRemoteSheet(context, widget.controller),
                    icon: Icon(Icons.cast_connected, color: colors.primary),
                  )
                else
                  IconButton(
                    tooltip: 'Cast',
                    onPressed: _pageMedia.isEmpty ? null : () => _showMedia(context),
                    icon: const Icon(Icons.cast_outlined),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.lock_outline, size: 17, color: colors.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _address,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _go(),
                      decoration: const InputDecoration(
                        hintText: 'Suchen oder URL eingeben',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  IconButton(onPressed: _go, icon: const Icon(Icons.arrow_forward_rounded)),
                ],
              ),
            ),
          ),
          if (_progress < 100)
            LinearProgressIndicator(value: _progress <= 0 ? null : _progress / 100, minHeight: 2),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: WebViewWidget(controller: _web)),
                if (_pageMedia.isNotEmpty)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: FilledButton.icon(
                      onPressed: () => _showMedia(context),
                      icon: Badge(
                        label: Text('${_pageMedia.length}'),
                        child: const Icon(Icons.video_collection_outlined),
                      ),
                      label: Text('${_pageMedia.length} Medien'),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(tooltip: 'Zurück', onPressed: () => _web.goBack(), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                  IconButton(tooltip: 'Vor', onPressed: () => _web.goForward(), icon: const Icon(Icons.arrow_forward_ios_rounded)),
                  IconButton(tooltip: 'Startseite', onPressed: _home, icon: const Icon(Icons.home_outlined)),
                  IconButton(tooltip: 'Neu laden', onPressed: () => _web.reload(), icon: const Icon(Icons.refresh_rounded)),
                  IconButton(tooltip: 'Medien suchen', onPressed: _scan, icon: const Icon(Icons.manage_search_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLibrary(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.78,
        child: _BrowserLibrarySheet(
          controller: widget.controller,
          onOpen: _openBrowserEntry,
        ),
      ),
    );
  }

  void _showMedia(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gefundene Medien', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text('${_pageMedia.length} Quellen auf dieser Seite', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(onPressed: _scan, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _pageMedia.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = _pageMedia[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_mediaIcon(item.kind))),
                      title: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_mediaLabel(item.kind)} • ${item.url.host}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.cast_outlined),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _cast(item);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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

  IconData _mediaIcon(MediaKind kind) => switch (kind) {
        MediaKind.audio => Icons.music_note_rounded,
        MediaKind.hls => Icons.stream_rounded,
        MediaKind.dash => Icons.hub_outlined,
        MediaKind.video => Icons.movie_outlined,
        MediaKind.unknown => Icons.insert_drive_file_outlined,
      };

  String _mediaLabel(MediaKind kind) => switch (kind) {
        MediaKind.hls => 'HLS',
        MediaKind.dash => 'DASH',
        MediaKind.video => 'Video',
        MediaKind.audio => 'Audio',
        MediaKind.unknown => 'Medium',
      };
}

class _BrowserLibrarySheet extends StatelessWidget {
  const _BrowserLibrarySheet({
    required this.controller,
    required this.onOpen,
  });

  final StreamFlowController controller;
  final ValueChanged<BrowserEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Browser-Bibliothek',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (controller.history.isNotEmpty)
                  TextButton(
                    onPressed: () => unawaited(controller.clearHistory()),
                    child: const Text('Verlauf löschen'),
                  ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.star_rounded), text: 'Favoriten'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Verlauf'),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (!controller.browserLibraryLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                return TabBarView(
                  children: [
                    _BrowserEntryList(
                      entries: controller.favorites,
                      emptyIcon: Icons.star_border_rounded,
                      emptyText: 'Noch keine Favoriten',
                      onOpen: onOpen,
                      onRemove: (entry) => unawaited(controller.removeFavorite(entry.url)),
                    ),
                    _BrowserEntryList(
                      entries: controller.history,
                      emptyIcon: Icons.history_toggle_off_rounded,
                      emptyText: 'Noch kein Browserverlauf',
                      onOpen: onOpen,
                      onRemove: (entry) => unawaited(controller.removeHistoryEntry(entry.url)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowserEntryList extends StatelessWidget {
  const _BrowserEntryList({
    required this.entries,
    required this.emptyIcon,
    required this.emptyText,
    required this.onOpen,
    required this.onRemove,
  });

  final List<BrowserEntry> entries;
  final IconData emptyIcon;
  final String emptyText;
  final ValueChanged<BrowserEntry> onOpen;
  final ValueChanged<BrowserEntry> onRemove;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 44),
            const SizedBox(height: 10),
            Text(emptyText),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(entry.url.host.isEmpty ? '?' : entry.url.host[0].toUpperCase())),
            title: Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(entry.url.host, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onOpen(entry),
            trailing: IconButton(
              tooltip: 'Entfernen',
              onPressed: () => onRemove(entry),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        );
      },
    );
  }
}
