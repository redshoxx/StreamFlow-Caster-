import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/app/streamflow_controller.dart';
import 'package:streamflow/src/models/browser_entry.dart';
import 'package:streamflow/src/models/detected_media.dart';
import 'package:streamflow/src/storage/browser_library_store.dart';

void main() {
  test('first visit waits for library load and is not overwritten', () async {
    final oldEntry = BrowserEntry(
      url: Uri.parse('https://old.example'),
      title: 'Old',
      timestamp: DateTime.utc(2026, 1, 1),
    );
    final store = _DelayedBrowserLibraryStore(
      BrowserLibrarySnapshot(history: [oldEntry], favorites: const []),
    );
    final controller = StreamFlowController(browserLibraryStore: store);

    final visit = controller.recordVisit(
      Uri.parse('https://new.example'),
      'New',
    );
    expect(controller.history, isEmpty);

    store.completeLoad();
    await visit;

    expect(controller.history.map((entry) => entry.url.host), [
      'new.example',
      'old.example',
    ]);
    expect(store.savedHistory.map((entry) => entry.url.host), [
      'new.example',
      'old.example',
    ]);
    controller.dispose();
  });

  test('detected media collection is capped', () async {
    final store = _DelayedBrowserLibraryStore(
      const BrowserLibrarySnapshot(history: [], favorites: []),
    )..completeLoad();
    final controller = StreamFlowController(browserLibraryStore: store);

    for (var index = 0; index < 250; index += 1) {
      controller.addDetectedMedia(_media(index));
    }

    expect(controller.detectedMedia, hasLength(200));
    expect(controller.detectedMedia.first.url.path, '/249.mp4');
    expect(controller.detectedMedia.last.url.path, '/50.mp4');
    controller.dispose();
  });
}

class _DelayedBrowserLibraryStore extends BrowserLibraryStore {
  _DelayedBrowserLibraryStore(this.snapshot);

  final BrowserLibrarySnapshot snapshot;
  final Completer<void> _loadGate = Completer<void>();
  List<BrowserEntry> savedHistory = const [];

  void completeLoad() {
    if (!_loadGate.isCompleted) _loadGate.complete();
  }

  @override
  Future<BrowserLibrarySnapshot> load() async {
    await _loadGate.future;
    return snapshot;
  }

  @override
  Future<void> saveHistory(List<BrowserEntry> entries) async {
    savedHistory = List<BrowserEntry>.from(entries);
  }

  @override
  Future<void> saveFavorites(List<BrowserEntry> entries) async {}
}

DetectedMedia _media(int index) => DetectedMedia(
      url: Uri.parse('https://cdn.example/$index.mp4'),
      kind: MediaKind.video,
      label: '$index',
    );
