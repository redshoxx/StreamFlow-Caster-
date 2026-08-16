import '../models/detected_media.dart';

abstract final class MediaDetector {
  static DetectedMedia? fromUrl(String rawUrl, {String? label, String? mime}) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }

    final lowerPath = uri.path.toLowerCase();
    final lowerUrl = uri.toString().toLowerCase();
    final queryMime = uri.queryParameters['mime'] ??
        uri.queryParameters['type'] ??
        uri.queryParameters['content_type'];
    final normalizedMime = (mime?.trim().isNotEmpty == true ? mime : queryMime)
        ?.toLowerCase();

    MediaKind kind = MediaKind.unknown;
    if (lowerUrl.contains('.m3u8') ||
        normalizedMime?.contains('mpegurl') == true ||
        lowerUrl.contains('format=m3u8')) {
      kind = MediaKind.hls;
    } else if (lowerUrl.contains('.mpd') ||
        normalizedMime?.contains('dash+xml') == true ||
        lowerUrl.contains('format=mpd')) {
      kind = MediaKind.dash;
    } else if (_videoExtensions.any(lowerPath.endsWith) ||
        normalizedMime?.startsWith('video/') == true ||
        lowerUrl.contains('mime=video')) {
      kind = MediaKind.video;
    } else if (_audioExtensions.any(lowerPath.endsWith) ||
        normalizedMime?.startsWith('audio/') == true ||
        lowerUrl.contains('mime=audio')) {
      kind = MediaKind.audio;
    }

    if (kind == MediaKind.unknown) return null;
    return DetectedMedia(
      url: uri,
      kind: kind,
      label: label,
      mimeType: mime ?? queryMime,
    );
  }

  static const _videoExtensions = <String>[
    '.mp4', '.m4v', '.mov', '.webm', '.mkv', '.ts', '.m2ts', '.3gp', '.ogv'
  ];

  static const _audioExtensions = <String>[
    '.mp3', '.aac', '.m4a', '.flac', '.ogg', '.opus', '.wav'
  ];

  static const hookScript = r'''
(() => {
  if (window.__streamFlowMediaHookInstalled) return;
  window.__streamFlowMediaHookInstalled = true;

  const seen = new Set();
  const report = (url, type, label) => {
    if (!url) return;
    try { url = new URL(url, document.baseURI).href; } catch (_) { return; }
    if (!/^https?:/i.test(url)) return;
    const key = url + '|' + (type || '');
    if (seen.has(key)) return;
    seen.add(key);
    try {
      if (window.StreamFlowMedia && window.StreamFlowMedia.postMessage) {
        window.StreamFlowMedia.postMessage(JSON.stringify({
          url: url,
          type: type || '',
          label: label || document.title || ''
        }));
      }
    } catch (_) {}
  };

  const originalFetch = window.fetch ? window.fetch.bind(window) : null;
  if (originalFetch) {
    window.fetch = (input, init) => {
      const url = typeof input === 'string' ? input : input && input.url;
      return originalFetch(input, init).then((response) => {
        try { report(response.url || url, response.headers.get('content-type'), document.title); } catch (_) {}
        return response;
      });
    };
  }

  if (window.XMLHttpRequest && XMLHttpRequest.prototype.open) {
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...args) {
      this.__streamFlowUrl = url;
      if (!this.__streamFlowHooked) {
        this.__streamFlowHooked = true;
        this.addEventListener('load', function() {
          try {
            report(this.responseURL || this.__streamFlowUrl, this.getResponseHeader('content-type'), document.title);
          } catch (_) {}
        });
      }
      return originalOpen.call(this, method, url, ...args);
    };
  }

  try {
    const observer = new PerformanceObserver((list) => {
      list.getEntries().forEach((entry) => report(entry.name, '', document.title));
    });
    observer.observe({entryTypes: ['resource']});
  } catch (_) {}
})();
''';

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
  document.querySelectorAll('a[href]').forEach((a) => push(a.href, '', a.textContent));

  try {
    performance.getEntriesByType('resource').forEach((entry) => push(entry.name, '', document.title));
  } catch (_) {}

  return JSON.stringify(items);
})()
''';
}
