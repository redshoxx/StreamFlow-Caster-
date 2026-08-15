import '../models/detected_media.dart';

abstract final class MediaDetector {
  static DetectedMedia? fromUrl(String rawUrl, {String? label, String? mime}) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }

    final lower = uri.path.toLowerCase();
    final normalizedMime = mime?.toLowerCase();

    MediaKind kind = MediaKind.unknown;
    if (lower.endsWith('.m3u8') || normalizedMime?.contains('mpegurl') == true) {
      kind = MediaKind.hls;
    } else if (lower.endsWith('.mpd') || normalizedMime?.contains('dash+xml') == true) {
      kind = MediaKind.dash;
    } else if (_videoExtensions.any(lower.endsWith) || normalizedMime?.startsWith('video/') == true) {
      kind = MediaKind.video;
    } else if (_audioExtensions.any(lower.endsWith) || normalizedMime?.startsWith('audio/') == true) {
      kind = MediaKind.audio;
    }

    if (kind == MediaKind.unknown) return null;
    return DetectedMedia(url: uri, kind: kind, label: label, mimeType: mime);
  }

  static const _videoExtensions = <String>[
    '.mp4', '.m4v', '.mov', '.webm', '.mkv', '.ts'
  ];

  static const _audioExtensions = <String>[
    '.mp3', '.aac', '.m4a', '.flac', '.ogg', '.wav'
  ];

  static const domScannerScript = r'''
(() => {
  const items = [];
  const seen = new Set();
  const push = (url, type, label) => {
    if (!url) return;
    try { url = new URL(url, document.baseURI).href; } catch (_) { return; }
    if (!/^https?:/i.test(url) || seen.has(url)) return;
    seen.add(url);
    items.push({ url, type: type || '', label: label || document.title || '' });
  };
  document.querySelectorAll('video,audio').forEach((el) => {
    push(el.currentSrc || el.src, el.getAttribute('type'), el.getAttribute('title'));
    el.querySelectorAll('source').forEach((s) => push(s.src, s.type, s.getAttribute('title')));
  });
  document.querySelectorAll('source').forEach((s) => push(s.src, s.type, s.getAttribute('title')));
  return JSON.stringify(items);
})()
''';
}
