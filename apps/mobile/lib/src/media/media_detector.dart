import '../models/detected_media.dart';

abstract final class MediaDetector {
  static DetectedMedia? fromUrl(String rawUrl, {String? label, String? mime}) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }

    final lowerPath = uri.path.toLowerCase();
    final lowerUrl = uri.toString().toLowerCase();
    String? queryMime;
    for (final entry in uri.queryParameters.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'mime' ||
          key == 'type' ||
          key == 'content_type' ||
          key == 'content-type' ||
          key == 'mimetype') {
        queryMime = entry.value;
        break;
      }
    }
    final normalizedMime = (mime?.trim().isNotEmpty == true ? mime : queryMime)
        ?.toLowerCase();

    MediaKind kind = MediaKind.unknown;
    if (lowerUrl.contains('.m3u8') ||
        lowerUrl.contains('.m3u?') ||
        normalizedMime?.contains('mpegurl') == true ||
        normalizedMime?.contains('vnd.apple.mpegurl') == true ||
        lowerUrl.contains('format=m3u8') ||
        lowerUrl.contains('manifest=m3u8')) {
      kind = MediaKind.hls;
    } else if (lowerUrl.contains('.mpd') ||
        normalizedMime?.contains('dash+xml') == true ||
        lowerUrl.contains('format=mpd') ||
        lowerUrl.contains('manifest=mpd')) {
      kind = MediaKind.dash;
    } else if (_videoExtensions.any(lowerPath.endsWith) ||
        normalizedMime?.startsWith('video/') == true ||
        normalizedMime == 'streamflow/video' ||
        lowerUrl.contains('mime=video') ||
        lowerUrl.contains('content_type=video')) {
      kind = MediaKind.video;
    } else if (_audioExtensions.any(lowerPath.endsWith) ||
        normalizedMime?.startsWith('audio/') == true ||
        normalizedMime == 'streamflow/audio' ||
        lowerUrl.contains('mime=audio') ||
        lowerUrl.contains('content_type=audio')) {
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
  let lastIntentAt = 0;

  const post = (payload) => {
    try {
      if (window.StreamFlowMedia && window.StreamFlowMedia.postMessage) {
        window.StreamFlowMedia.postMessage(JSON.stringify(payload));
      }
    } catch (_) {}
  };

  const signalIntent = (reason) => {
    const now = Date.now();
    if (now - lastIntentAt < 450) return;
    lastIntentAt = now;
    post({ event: 'intent', reason: reason || 'media', label: document.title || '' });
  };

  const report = (url, type, label) => {
    if (!url) return;
    try { url = new URL(url, document.baseURI).href; } catch (_) { return; }
    if (!/^https?:/i.test(url)) return;
    const key = url + '|' + (type || '');
    if (seen.has(key)) return;
    seen.add(key);
    post({
      event: 'media',
      url: url,
      type: type || '',
      label: label || document.title || ''
    });
  };

  const reportElement = (el) => {
    if (!el) return;
    const tag = (el.tagName || '').toLowerCase();
    if (tag === 'video' || tag === 'audio') {
      report(
        el.currentSrc || el.src || el.getAttribute('src'),
        el.getAttribute('type') || (tag === 'video' ? 'streamflow/video' : 'streamflow/audio'),
        el.getAttribute('title') || el.getAttribute('aria-label') || document.title
      );
      try {
        el.querySelectorAll('source').forEach((source) => {
          report(
            source.src || source.getAttribute('src'),
            source.type || source.getAttribute('type') || (tag === 'video' ? 'streamflow/video' : 'streamflow/audio'),
            source.getAttribute('title') || document.title
          );
        });
      } catch (_) {}
    }

    const attributes = [
      'src', 'href', 'data-src', 'data-url', 'data-file', 'data-video',
      'data-stream', 'data-hls', 'data-m3u8', 'data-mpd'
    ];
    for (const name of attributes) {
      try {
        const value = el.getAttribute && el.getAttribute(name);
        if (value) report(value, '', el.getAttribute('title') || el.textContent || document.title);
      } catch (_) {}
    }
  };

  const scanDom = () => {
    try {
      document.querySelectorAll(
        'video,audio,source,a[href],[data-src],[data-url],[data-file],[data-video],[data-stream],[data-hls],[data-m3u8],[data-mpd]'
      ).forEach(reportElement);
    } catch (_) {}
    try {
      performance.getEntriesByType('resource').forEach((entry) => {
        const initiator = (entry.initiatorType || '').toLowerCase();
        const type = initiator === 'video'
          ? 'streamflow/video'
          : initiator === 'audio'
            ? 'streamflow/audio'
            : '';
        report(entry.name, type, document.title);
      });
    } catch (_) {}
  };

  const scheduleScans = () => {
    [0, 80, 250, 700, 1500, 3000].forEach((delay) => setTimeout(scanDom, delay));
  };

  const originalFetch = window.fetch ? window.fetch.bind(window) : null;
  if (originalFetch) {
    window.fetch = (input, init) => {
      const requestUrl = typeof input === 'string' ? input : input && input.url;
      report(requestUrl, '', document.title);
      return originalFetch(input, init).then((response) => {
        try {
          report(
            response.url || requestUrl,
            response.headers && response.headers.get ? response.headers.get('content-type') : '',
            document.title
          );
        } catch (_) {}
        return response;
      });
    };
  }

  if (window.XMLHttpRequest && XMLHttpRequest.prototype.open) {
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...args) {
      this.__streamFlowUrl = url;
      report(url, '', document.title);
      if (!this.__streamFlowHooked) {
        this.__streamFlowHooked = true;
        this.addEventListener('load', function() {
          try {
            report(
              this.responseURL || this.__streamFlowUrl,
              this.getResponseHeader('content-type'),
              document.title
            );
          } catch (_) {}
        });
      }
      return originalOpen.call(this, method, url, ...args);
    };
  }

  if (window.HTMLMediaElement && HTMLMediaElement.prototype.play) {
    const originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function(...args) {
      signalIntent('play');
      reportElement(this);
      scheduleScans();
      return originalPlay.apply(this, args);
    };
  }

  if (window.Element && Element.prototype.setAttribute) {
    const originalSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
      const result = originalSetAttribute.call(this, name, value);
      const lowerName = String(name || '').toLowerCase();
      if (lowerName === 'src' ||
          lowerName === 'href' ||
          lowerName.startsWith('data-')) {
        reportElement(this);
      }
      return result;
    };
  }

  document.addEventListener('click', (event) => {
    try {
      const target = event.target && event.target.closest
        ? event.target.closest('video,audio,button,a,[role="button"],[class*="play" i],[id*="play" i],[class*="player" i],[id*="player" i]')
        : null;
      if (!target) return;
      const marker = ((target.id || '') + ' ' + (target.className || '') + ' ' + (target.getAttribute && target.getAttribute('aria-label') || '')).toLowerCase();
      const tag = (target.tagName || '').toLowerCase();
      const likelyMedia = tag === 'video' || tag === 'audio' ||
        marker.includes('play') || marker.includes('player') || marker.includes('video') || marker.includes('watch') || marker.includes('stream');
      if (!likelyMedia) return;
      signalIntent('click');
      reportElement(target);
      scheduleScans();
    } catch (_) {}
  }, true);

  window.addEventListener('blur', () => {
    setTimeout(() => {
      try {
        const active = document.activeElement;
        if (active && (active.tagName || '').toLowerCase() === 'iframe') {
          signalIntent('iframe');
          scheduleScans();
        }
      } catch (_) {}
    }, 0);
  });

  try {
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === 'attributes') reportElement(mutation.target);
        mutation.addedNodes && mutation.addedNodes.forEach((node) => {
          if (node && node.nodeType === 1) {
            reportElement(node);
            try { node.querySelectorAll && node.querySelectorAll('video,audio,source').forEach(reportElement); } catch (_) {}
          }
        });
      }
    });
    observer.observe(document.documentElement || document, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ['src', 'href', 'data-src', 'data-url', 'data-file', 'data-video', 'data-stream', 'data-hls', 'data-m3u8', 'data-mpd']
    });
  } catch (_) {}

  try {
    const observer = new PerformanceObserver((list) => {
      list.getEntries().forEach((entry) => {
        const initiator = (entry.initiatorType || '').toLowerCase();
        const type = initiator === 'video'
          ? 'streamflow/video'
          : initiator === 'audio'
            ? 'streamflow/audio'
            : '';
        report(entry.name, type, document.title);
      });
    });
    observer.observe({entryTypes: ['resource']});
  } catch (_) {}

  scanDom();
})();
''';

  static const domScannerScript = r'''
(() => {
  const items = [];
  const seen = new Set();
  const push = (url, type, label) => {
    if (!url) return;
    try { url = new URL(url, document.baseURI).href; } catch (_) { return; }
    if (!/^https?:/i.test(url) || seen.has(url + '|' + (type || ''))) return;
    seen.add(url + '|' + (type || ''));
    items.push({ url, type: type || '', label: label || document.title || '' });
  };

  document.querySelectorAll('video,audio').forEach((el) => {
    const tag = (el.tagName || '').toLowerCase();
    const fallbackType = tag === 'audio' ? 'streamflow/audio' : 'streamflow/video';
    push(
      el.currentSrc || el.src || el.getAttribute('src'),
      el.getAttribute('type') || fallbackType,
      el.getAttribute('title') || el.getAttribute('aria-label')
    );
    el.querySelectorAll('source').forEach((s) => push(
      s.src || s.getAttribute('src'),
      s.type || s.getAttribute('type') || fallbackType,
      s.getAttribute('title')
    ));
  });
  document.querySelectorAll('source').forEach((s) => push(s.src, s.type, s.getAttribute('title')));
  document.querySelectorAll('a[href]').forEach((a) => push(a.href, '', a.textContent));
  document.querySelectorAll('[data-src],[data-url],[data-file],[data-video],[data-stream],[data-hls],[data-m3u8],[data-mpd]').forEach((el) => {
    ['data-src','data-url','data-file','data-video','data-stream','data-hls','data-m3u8','data-mpd'].forEach((name) => {
      push(el.getAttribute(name), '', el.getAttribute('title') || el.textContent);
    });
  });

  try {
    performance.getEntriesByType('resource').forEach((entry) => {
      const initiator = (entry.initiatorType || '').toLowerCase();
      const type = initiator === 'video'
        ? 'streamflow/video'
        : initiator === 'audio'
          ? 'streamflow/audio'
          : '';
      push(entry.name, type, document.title);
    });
  } catch (_) {}

  return JSON.stringify(items);
})()
''';
}
