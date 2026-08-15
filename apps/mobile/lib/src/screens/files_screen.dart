import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  PlatformFile? _selected;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (!mounted || result == null || result.files.isEmpty) return;
    setState(() => _selected = result.files.single);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lokale Dateien', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add),
              label: const Text('Video auswählen'),
            ),
            const SizedBox(height: 20),
            if (_selected != null)
              ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: Text(_selected!.name),
                subtitle: Text('${_selected!.size} Bytes'),
              ),
          ],
        ),
      ),
    );
  }
}
