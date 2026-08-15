import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import 'browser_screen.dart';
import 'cast_remote_sheet.dart';
import 'devices_screen.dart';
import 'files_screen.dart';
import 'home_screen.dart';
import 'media_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _controller = StreamFlowController();
  var _pageIndex = 0;
  var _browserEpoch = 0;
  Uri? _browserLaunchUri;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openBrowser(Uri? uri) {
    setState(() {
      if (uri != null) {
        _browserLaunchUri = uri;
        _browserEpoch += 1;
      }
      _pageIndex = 1;
    });
  }

  void _openPage(int index) => setState(() => _pageIndex = index);

  void _showQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schnellaktion',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              _QuickSheetTile(
                icon: Icons.folder_rounded,
                title: 'Lokale Datei übertragen',
                subtitle: 'Video vom Smartphone an StreamFlow TV senden',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openPage(3);
                },
              ),
              _QuickSheetTile(
                icon: Icons.tv_rounded,
                title: 'Gerät verbinden',
                subtitle: 'StreamFlow TV im lokalen Netzwerk suchen',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openPage(4);
                },
              ),
              _QuickSheetTile(
                icon: Icons.language_rounded,
                title: 'Webseite öffnen',
                subtitle: 'Browser starten und Medien automatisch erkennen',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openBrowser(null);
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.security_rounded, size: 17, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Adblocker ist im Browser standardmäßig aktiv.',
                      style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pages = <Widget>[
          HomeScreen(
            controller: _controller,
            onOpenBrowser: _openBrowser,
            onOpenFiles: () => _openPage(3),
            onOpenDevices: () => _openPage(4),
            onOpenMedia: () => _openPage(2),
          ),
          BrowserScreen(
            key: ValueKey('browser-$_browserEpoch'),
            controller: _controller,
            initialUri: _browserLaunchUri,
          ),
          MediaScreen(controller: _controller),
          FilesScreen(controller: _controller),
          DevicesScreen(controller: _controller),
          SettingsScreen(
            controller: _controller,
            onOpenFiles: () => _openPage(3),
            onOpenDevices: () => _openPage(4),
          ),
        ];

        return Scaffold(
          body: IndexedStack(index: _pageIndex, children: pages),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_controller.isCasting)
                _NowPlayingBar(
                  controller: _controller,
                  onTap: () => showCastRemoteSheet(context, _controller),
                ),
              _ModernBottomBar(
                pageIndex: _pageIndex,
                onHome: () => _openPage(0),
                onBrowser: () => _openBrowser(null),
                onQuickAction: _showQuickActions,
                onMedia: () => _openPage(2),
                onSettings: () => _openPage(5),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModernBottomBar extends StatelessWidget {
  const _ModernBottomBar({
    required this.pageIndex,
    required this.onHome,
    required this.onBrowser,
    required this.onQuickAction,
    required this.onMedia,
    required this.onSettings,
  });

  final int pageIndex;
  final VoidCallback onHome;
  final VoidCallback onBrowser;
  final VoidCallback onQuickAction;
  final VoidCallback onMedia;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF091522),
      elevation: 12,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _NavButton(
                selected: pageIndex == 0,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Home',
                onTap: onHome,
              ),
              _NavButton(
                selected: pageIndex == 1,
                icon: Icons.public_outlined,
                selectedIcon: Icons.public_rounded,
                label: 'Browser',
                onTap: onBrowser,
              ),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'Schnellaktion öffnen',
                    child: InkResponse(
                      onTap: onQuickAction,
                      radius: 30,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.34),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(Icons.add_rounded, color: colors.onPrimary, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
              _NavButton(
                selected: pageIndex == 2,
                icon: Icons.video_library_outlined,
                selectedIcon: Icons.video_library_rounded,
                label: 'Medien',
                onTap: onMedia,
              ),
              _NavButton(
                selected: pageIndex == 5,
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: 'Einstellungen',
                onTap: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontSize: 9.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSheetTile extends StatelessWidget {
  const _QuickSheetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: colors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({required this.controller, required this.onTap});

  final StreamFlowController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final media = controller.activeMedia!;
    final device = controller.activeDevice!;
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: const Color(0xFF0D1B2A),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.cast_connected, color: colors.primary, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Auf ${device.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_up_rounded, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
