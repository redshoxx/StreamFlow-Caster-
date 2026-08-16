import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/media/media_detector.dart';
import 'package:streamflow/src/models/detected_media.dart';

void main() {
  test('detects HLS', () {
    final media = MediaDetector.fromUrl('https://cdn.example.com/master.m3u8');
    expect(media, isNotNull);
    expect(media!.kind, MediaKind.hls);
  });

  test('detects MP4 with query string', () {
    final media = MediaDetector.fromUrl('https://cdn.example.com/video.mp4?token=abc');
    expect(media, isNotNull);
    expect(media!.kind, MediaKind.video);
  });

  test('detects dynamic video endpoint from synthetic media hint', () {
    final media = MediaDetector.fromUrl(
      'https://cdn.example.com/playback?id=42',
      mime: 'streamflow/video',
    );
    expect(media, isNotNull);
    expect(media!.kind, MediaKind.video);
  });

  test('detects HLS from content type query', () {
    final media = MediaDetector.fromUrl(
      'https://cdn.example.com/playlist?id=42&content_type=application/vnd.apple.mpegurl',
    );
    expect(media, isNotNull);
    expect(media!.kind, MediaKind.hls);
  });

  test('rejects non-http URLs', () {
    expect(MediaDetector.fromUrl('file:///tmp/video.mp4'), isNull);
  });
}
