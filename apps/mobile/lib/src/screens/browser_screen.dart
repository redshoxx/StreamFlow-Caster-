import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/streamflow_controller.dart';
import '../browser/ad_blocker.dart';
import '../browser/browser_tab_session.dart';
import '../models/browser_entry.dart';
import '../models/cast_device.dart';
import '../models/detected_media.dart';
import 'cast_media_dialog.dart';
import 'cast_remote_sheet.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.controller,
    this.initialUri,
  });

  final StreamFlowController controller;
  final Uri? initialUri;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const _maxTabs = 24;

  final _adBlocker = AdBlocker();
  final List<BrowserTabSession> _tabs = <BrowserTabSession>[];
  final Map<int, int> _handledIntentSerial = <int, int>{};
  final Map<int, int> _handledDetectionSerial = <int, int>{};
  final Set<String> _connectionPromptedPages = <String>{};
  final Set<String> _promptedMedia = <String>{};
  var _activeIndex = 0;
  var _nextTabId = 1;
  var _adBlockEnabled = true;
  var _castPromptOpen = false;

  BrowserTabSession get _active => _tabs[_activeIndex];

  @override
  void initState() {
    super.initState();
    _addInitialTab(widget.initialUri ?? Uri.parse(BrowserTabSession.homeUrl));
    unawaited(_loadAdBlockSetting());
  }

  void _addInitialTab(Uri uri) {
    final session = _makeSession(uri);
    _tabs.add(session);
    unawaited(session.initialize(enableAdBlock: _adBlockEnabled));
  }

  BrowserTabSession _makeSession(Uri uri) => BrowserTabSession(
        id: _nextTabId++,
        initialUri: uri,
        appController: widget.controller,
        adBlocker: _adBlocker,
        onChanged: _onTabChanged,
      );

  void _onTabChanged() {
    if (!mounted || _tabs.isEmpty) return;
    setState(() {});

    final active = _active;
    final intentSerial = active.mediaIntentSerial;
    final handledIntent = _handledIntentSerial[active.id] ?? 0;
    if (intentSerial > handledIntent) {
      _handledIntentSerial[active.id] = intentSerial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handleMediaIntent(active));
      });
    }

    final detectionSerial = active.mediaDetectionSerial;
    final handledDetection = _handledDetectionSerial[active.id] ?? 0;
    if (detectionSerial > handledDetection) {
      _handledDetectionSerial[active.id] = detectionSerial;
      if (_hasRecentMediaIntent(active) && active.pageMedia.isNotEmpty) {
        final media = active.pageMedia.last;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_promptForDetectedMedia(active, media));
        });
      }
    }
  }

  bool _hasRecentMediaIntent(BrowserTabSession tab) {
    final at = tab.lastMediaIntentAt;
    return at != null && DateTime.now().difference(at) < const Duration(seconds: 9);
  }

  Future<void> _handleMediaIntent(BrowserTabSession tab) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || _tabs.isEmpty || _active.id != tab.id || _castPromptOpen) {
      return;
    }

    await tab.scan();
    if (!mounted || _active.id != tab.id || !_hasRecentMediaIntent(tab)) return;

    if (tab.pageMedia.isNotEmpty) {
      await _promptForDetectedMedia(tab, tab.pageMedia.last);
      return;
    }

    final preferred = widget.controller.preferredDevice;
    if (preferred != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'TV bereit: ${preferred.name}. StreamFlow sucht noch nach der Videoquelle.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }

    final pageKey = '${tab.id}|${tab.currentUri ?? ''}';
    if (_connectionPromptedPages.contains(pageKey)) return;
    _connectionPromptedPages.add(pageKey);
    _castPromptOpen = true;
    final connect = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cast_rounded),
        title: const Text('Video gestartet'),
        content: const Text(
          'StreamFlow sucht gerade nach der abspielbaren Videoquelle. Möchtest du den Fernseher jetzt schon verbinden? Sobald die Quelle erkannt wurde, kann sie direkt übertragen werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Später'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.tv_rounded),
            label: const Text('TV verbinden'),
          ),
        ],
      ),
    );
    _castPromptOpen = false;
    if (connect == true && mounted) await _connectTv();
  }

  Future<void> _promptForDetectedMedia(
    BrowserTabSession tab,
    DetectedMedia media,
  ) async {
    if (!mounted || _tabs.isEmpty || _active.id != tab.id || _castPromptOpen) {
      return;
    }
    final key = '${tab.id}|${tab.currentUri ?? ''}|${media.url}';
    if (_promptedMedia.contains(key)) return;
    _promptedMedia.add(key);

    final preferred = widget.controller.preferredDevice;
    _castPromptOpen = true;
    final castNow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.video_collection_rounded),
        title: const Text('Video erkannt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              media.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              preferred == null
                  ? 'Möchtest du dieses Video auf einem Fernseher anzeigen?'
                  : 'Möchtest du dieses Video auf ${preferred.name} bzw. einem anderen Gerät anzeigen?',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Nicht jetzt'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.cast_rounded),
            label: Text(preferred == null ? 'Gerät wählen' : 'Auf TV anzeigen'),
          ),
        ],
      ),
    );
    _castPromptOpen = false;
    if (castNow == true && mounted) await _cast(media);
  }

  Future<void> _loadAdBlockSetting() async {
    try {
      final enabled = await _adBlocker.loadEnabled();
      if (!mounted || enabled == _adBlockEnabled) return;
      setState(() => _adBlockEnabled = enabled);
      for (final tab in _tabs) {
        await tab.setAdBlockEnabled(enabled);
      }
    } catch (_) {}
  }

  Future<void> _toggleAdBlocker() async {
    final enabled = !_adBlockEnabled;
    setState(() => _adBlockEnabled = enabled);
    try {
      await _adBlocker.saveEnabled(enabled);
    } catch (_) {}
    for (final tab in List<BrowserTabSession>.of(_tabs)) {
      await tab.setAdBlockEnabled(enabled);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Werbung, Pop-ups und Web-Push werden blockiert.'
              : 'Schutz für diese Browsersitzung deaktiviert.',
        ),
      ),
    );
  }

  void _newTab({Uri? uri}) {
    if (_tabs.length >= _maxTabs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximal 24 Tabs gleichzeitig.')),
      );
      return;
    }
    final session = _makeSession(uri ?? Uri.parse(BrowserTabSession.homeUrl));
    setState(() {
      _tabs.add(session);
      _activeIndex = _tabs.length - 1;
    });
    unawaited(session.initialize(enableAdBlock: _adBlockEnabled));
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.length == 1) {
      final old = _tabs.single;
      final replacement = _makeSession(Uri.parse(BrowserTabSession.homeUrl));
      setState(() {
        _tabs[0] = replacement;
        _activeIndex = 0;
      });
      _handledIntentSerial.remove(old.id);
      _handledDetectionSerial.remove(old.id);
      old.dispose();
      unawaited(replacement.initialize(enableAdBlock: _adBlockEnabled));
      return;
    }

    final old = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (_activeIndex > index) {
        _activeIndex -= 1;
      } else if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      }
    });
    _handledIntentSerial.remove(old.id);
    _handledDetectionSerial.remove(old.id);
    old.dispose();
  }

  Future<void> _toggleFavorite() async {
    final uri = _active.currentUri;
    if (uri == null) return;
    final wasFavorite = widget.controller.isFavorite(uri);
    await widget.controller.toggleFavorite(uri, _active.pageTitle);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasFavorite ? 'Aus Favoriten entfernt.' : 'Zu Favoriten hinzugefügt.',
        ),
      ),
    );
  }

  void _openBrowserEntry(BrowserEntry entry) {
    Navigator.of(context).pop();
    unawaited(_active.openUri(entry.url));
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final favorite = widget.controller.isFavorite(_active.currentUri);
    final preferredDevice = widget.controller.preferredDevice;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'StreamFlow',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _active.pageTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: favorite ? 'Favorit entfernen' : 'Favorit hinzufügen',
                  onPressed: _active.currentUri == null ? null : _toggleFavorite,
                  icon: Icon(
                    favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Favoriten und Verlauf',
                  onPressed: () => _showLibrary(context),
                  icon: const Icon(Icons.bookmarks_outlined),
                ),
                IconButton(
                  tooltip: _adBlockEnabled
                      ? 'Schutz aktiv • ${_active.blockedAds} blockiert'
                      : 'Schutz deaktiviert',
                  onPressed: _toggleAdBlocker,
                  icon: Badge(
                    isLabelVisible: _adBlockEnabled && _active.blockedAds > 0,
                    label: Text(
                      _active.blockedAds > 99 ? '99+' : '${_active.blockedAds}',
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      color: _adBlockEnabled
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.controller.isCasting)
                  IconButton(
                    tooltip: 'Wiedergabe steuern',
                    onPressed: () =>
                        showCastRemoteSheet(context, widget.controller),
                    icon: Icon(Icons.cast_connected, color: colors.primary),
                  )
                else
                  IconButton(
                    tooltip: _active.pageMedia.isEmpty
                        ? preferredDevice == null
                            ? 'Mit TV verbinden'
                            : 'TV ändern: ${preferredDevice.name}'
                        : 'Auf TV übertragen',
                    onPressed: () => _active.pageMedia.isEmpty
                        ? _connectTv()
                        : _showMedia(context),
                    icon: Icon(
                      preferredDevice == null
                          ? Icons.cast_outlined
                          : Icons.cast_connected,
                      color: preferredDevice == null ? null : colors.primary,
                    ),
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
                  Icon(
                    _active.secure
                        ? Icons.lock_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 17,
                    color: _active.secure
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: ValueKey(_active.id),
                      controller: _active.address,
                      focusNode: _active.addressFocus,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) {
                        FocusScope.of(context).unfocus();
                        unawaited(_active.goFromAddress());
                      },
                      decoration: const InputDecoration(
                        hintText: 'Suchen oder Webadresse',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  _TabCountButton(
                    count: _tabs.length,
                    onTap: _showTabs,
                  ),
                  IconButton(
                    tooltip: 'Öffnen',
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      unawaited(_active.goFromAddress());
                    },
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (preferredDevice != null && !widget.controller.isCasting)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.cast_connected, color: colors.onPrimaryContainer),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'TV bereit: ${preferredDevice.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _connectTv,
                    child: const Text('Ändern'),
                  ),
                ],
              ),
            ),
          if (_active.progress < 100)
            LinearProgressIndicator(
              value: _active.progress <= 0 ? null : _active.progress / 100,
              minHeight: 2,
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: WebViewWidget(
                    key: ValueKey('web-${_active.id}'),
                    controller: _active.web,
                  ),
                ),
                if (_active.pageMedia.isNotEmpty)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: FilledButton.icon(
                      onPressed: () => _showMedia(context),
                      icon: Badge(
                        label: Text('${_active.pageMedia.length}'),
                        child: const Icon(Icons.video_collection_outlined),
                      ),
                      label: const Text('Medien'),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    tooltip: 'Zurück',
                    onPressed: () => unawaited(_active.goBack()),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  IconButton(
                    tooltip: 'Vor',
                    onPressed: () => unawaited(_active.goForward()),
                    icon: const Icon(Icons.arrow_forward_ios_rounded),
                  ),
                  IconButton(
                    tooltip: 'Neuer Tab',
                    onPressed: _newTab,
                    icon: const Icon(Icons.add_box_outlined),
                  ),
                  IconButton(
                    tooltip: 'Startseite',
                    onPressed: () => unawaited(_active.home()),
                    icon: const Icon(Icons.home_outlined),
                  ),
                  IconButton(
                    tooltip: 'Neu laden',
                    onPressed: () => unawaited(_active.reload()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Medien neu erkennen',
                    onPressed: () => unawaited(_active.scan()),
                    icon: const Icon(Icons.manage_search_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTabs() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_tabs.length} ${_tabs.length == 1 ? 'Tab' : 'Tabs'}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _newTab();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Neu'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final active = index == _activeIndex;
                    return Card(
                      color: active
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          tab.pageTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          tab.currentUri?.host.isNotEmpty == true
                              ? tab.currentUri!.host
                              : 'Neuer Tab',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          setState(() => _activeIndex = index);
                          Navigator.of(sheetContext).pop();
                        },
                        trailing: IconButton(
                          tooltip: 'Tab schließen',
                          onPressed: () {
                            _closeTab(index);
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
        heightFactor: 0.75,
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
                        Text(
                          'Gefundene Medien',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${_active.pageMedia.length} abspielbare Quellen',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Neu erkennen',
                    onPressed: () => unawaited(_active.scan()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _active.pageMedia.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = _active.pageMedia[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_mediaIcon(item.kind))),
                      title: Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_mediaLabel(item.kind)} • ${item.url.host}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Future<void> _connectTv() async {
    if (!mounted) return;
    final target = await showDialog<CastTarget>(
      context: context,
      builder: (_) => CastMediaDialog(
        preferredDeviceId: widget.controller.preferredDevice?.id,
      ),
    );
    if (!mounted || target == null) return;
    widget.controller.setPreferredDevice(target.device);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'TV bereit: ${target.device.name}. Starte jetzt ein Video – StreamFlow erkennt die Quelle automatisch.',
          ),
        ),
      );
  }

  Future<void> _cast(DetectedMedia item) async {
    final target = await showDialog<CastTarget>(
      context: context,
      builder: (_) => CastMediaDialog(
        media: item,
        preferredDeviceId: widget.controller.preferredDevice?.id,
      ),
    );
    if (!mounted || target == null) return;
    widget.controller.startCasting(
      target.device,
      item,
      pairingCode: target.pairingCode,
    );
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

class _TabCountButton extends StatelessWidget {
  const _TabCountButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Tabs',
      onPressed: onTap,
      icon: Container(
        width: 25,
        height: 25,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
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
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
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
                      onRemove: (entry) =>
                          unawaited(controller.removeFavorite(entry.url)),
                    ),
                    _BrowserEntryList(
                      entries: controller.history,
                      emptyIcon: Icons.history_toggle_off_rounded,
                      emptyText: 'Noch kein Browserverlauf',
                      onOpen: onOpen,
                      onRemove: (entry) =>
                          unawaited(controller.removeHistoryEntry(entry.url)),
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
            leading: CircleAvatar(
              child: Text(
                entry.url.host.isEmpty
                    ? '?'
                    : entry.url.host[0].toUpperCase(),
              ),
            ),
            title: Text(
              entry.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              entry.url.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
