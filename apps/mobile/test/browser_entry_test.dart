import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/models/browser_entry.dart';

void main() {
  test('BrowserEntry survives JSON serialization', () {
    final entry = BrowserEntry(
      url: Uri.parse('https://example.com/watch?id=42'),
      title: 'Example video',
      timestamp: DateTime.utc(2026, 8, 15, 8, 0),
    );

    final restored = BrowserEntry.fromJson(entry.toJson());

    expect(restored, isNotNull);
    expect(restored!.url, entry.url);
    expect(restored.title, entry.title);
    expect(restored.timestamp.toUtc(), entry.timestamp);
  });

  test('BrowserEntry rejects unsupported schemes', () {
    final restored = BrowserEntry.fromJson(<String, Object?>{
      'url': 'file:///tmp/video.mp4',
      'title': 'Local',
      'timestamp': DateTime.utc(2026, 8, 15).toIso8601String(),
    });

    expect(restored, isNull);
  });
}
