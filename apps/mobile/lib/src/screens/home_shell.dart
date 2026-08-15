import 'package:flutter/material.dart';

import 'browser_screen.dart';
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

  final _pages = const [
    BrowserScreen(),
    MediaScreen(),
    FilesScreen(),
    DevicesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: 'Browser'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), label: 'Medien'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Dateien'),
          NavigationDestination(icon: Icon(Icons.cast), label: 'Geräte'),
        ],
      ),
    );
  }
}
