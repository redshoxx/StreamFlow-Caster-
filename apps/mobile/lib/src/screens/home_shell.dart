import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import 'browser_screen.dart';
import 'cast_remote_sheet.dart';
import 'devices_screen.dart';
import 'files_screen.dart';
import 'media_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;
  final _controller = StreamFlowController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pages = <Widget>[
          BrowserScreen(controller: _controller),
          MediaScreen(controller: _controller),
          const FilesScreen(),
          DevicesScreen(controller: _controller),
        ];

        return Scaffold(
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_controller.isCasting)
                _NowPlayingBar(
                  controller: _controller,
                  onTap: () => showCastRemoteSheet(context, _controller),
                ),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) => setState(() => _index = value),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.public), selectedIcon: Icon(Icons.public), label: 'Browser'),
                  NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Medien'),
                  NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Dateien'),
                  NavigationDestination(icon: Icon(Icons.cast_outlined), selectedIcon: Icon(Icons.cast_connected), label: 'Geräte'),
                ],
              ),
            ],
          ),
        );
      },
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
      color: colors.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.cast_connected, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_up),
            ],
          ),
        ),
      ),
    );
  }
}
