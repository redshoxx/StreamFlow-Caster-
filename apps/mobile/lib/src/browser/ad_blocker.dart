import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AdBlocker {
  AdBlocker([this._preferences]);

  static const _enabledKey = 'streamflow.adblock.enabled.v1';

  static const blockedHosts = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'amazon-adsystem.com',
    'adnxs.com',
    'adsrvr.org',
    'criteo.com',
    'criteo.net',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'casalemedia.com',
    'smartadserver.com',
    'media.net',
    'taboola.com',
    'outbrain.com',
    'scorecardresearch.com',
    'quantserve.com',
    'google-analytics.com',
  ];

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  Future<bool> loadEnabled() async =>
      await _prefs.getBool(_enabledKey) ?? true;

  Future<void> saveEnabled(bool enabled) =>
      _prefs.setBool(_enabledKey, enabled);

  bool shouldBlockUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    final host = uri?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;

    return blockedHosts.any(
      (blocked) => host == blocked || host.endsWith('.$blocked'),
    );
  }

  String get javaScript {
    final hosts = jsonEncode(blockedHosts);
    return '''
(() => {
  const blockedHosts = $hosts;
  const isBlocked = (value) => {
    if (!value) return false;
    try {
      const url = new URL(value, document.baseURI);
      const host = url.hostname.toLowerCase();
      return blockedHosts.some((blocked) => host === blocked || host.endsWith('.' + blocked));
    } catch (_) {
      return false;
    }
  };

  const report = (count) => {
    if (!count) return;
    try {
      if (window.StreamFlowAdBlock && window.StreamFlowAdBlock.postMessage) {
        window.StreamFlowAdBlock.postMessage(String(count));
      }
    } catch (_) {}
  };

  const selectors = [
    '.adsbygoogle',
    '[data-ad-slot]',
    '[data-ad-client]',
    '[id^="google_ads_"]',
    '[id*="google_ads"]',
    '[class*="ad-container"]',
    '[class*="ad_container"]',
    '[class*="ad-wrapper"]',
    '[class*="ad_wrapper"]',
    'iframe[src*="doubleclick.net"]',
    'iframe[src*="googlesyndication.com"]',
    'iframe[src*="amazon-adsystem.com"]'
  ];
  const selectorText = selectors.join(',');

  const removeElement = (element) => {
    if (!element || !element.isConnected) return 0;
    element.remove();
    return 1;
  };

  const cleanNode = (node) => {
    if (!(node instanceof Element)) return 0;
    let removed = 0;

    try {
      if (node.matches(selectorText)) return removeElement(node);
    } catch (_) {}

    if (node.hasAttribute && node.hasAttribute('src') && isBlocked(node.getAttribute('src'))) {
      return removeElement(node);
    }

    try {
      node.querySelectorAll(selectorText).forEach((element) => {
        removed += removeElement(element);
      });
      node.querySelectorAll('iframe[src], img[src], script[src]').forEach((element) => {
        if (isBlocked(element.getAttribute('src'))) {
          removed += removeElement(element);
        }
      });
    } catch (_) {}
    return removed;
  };

  const cleanDocument = () => {
    if (!document.documentElement) return;
    let removed = 0;
    try {
      document.querySelectorAll(selectorText).forEach((element) => {
        removed += removeElement(element);
      });
      document.querySelectorAll('iframe[src], img[src], script[src]').forEach((element) => {
        if (isBlocked(element.getAttribute('src'))) {
          removed += removeElement(element);
        }
      });
    } catch (_) {}
    report(removed);
  };

  if (!window.__streamFlowAdBlockInstalled) {
    window.__streamFlowAdBlockInstalled = true;

    const originalOpen = window.open ? window.open.bind(window) : null;
    if (originalOpen) {
      window.open = (url, ...args) => {
        if (url && isBlocked(url)) {
          report(1);
          return null;
        }
        return originalOpen(url, ...args);
      };
    }

    const originalFetch = window.fetch ? window.fetch.bind(window) : null;
    if (originalFetch) {
      window.fetch = (input, init) => {
        const url = typeof input === 'string' ? input : input && input.url;
        if (url && isBlocked(url)) {
          report(1);
          return Promise.resolve(new Response('', {status: 204}));
        }
        return originalFetch(input, init);
      };
    }

    if (window.XMLHttpRequest && XMLHttpRequest.prototype.open) {
      const originalXhrOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...args) {
        if (url && isBlocked(url)) {
          report(1);
          return originalXhrOpen.call(this, method, 'data:text/plain,', ...args);
        }
        return originalXhrOpen.call(this, method, url, ...args);
      };
    }

    if (navigator.sendBeacon) {
      const originalBeacon = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = (url, data) => {
        if (url && isBlocked(url)) {
          report(1);
          return true;
        }
        return originalBeacon(url, data);
      };
    }

    if (document.documentElement) {
      const observer = new MutationObserver((mutations) => {
        let removed = 0;
        for (const mutation of mutations) {
          mutation.addedNodes.forEach((node) => {
            removed += cleanNode(node);
          });
        }
        report(removed);
      });
      observer.observe(document.documentElement, {childList: true, subtree: true});
    }
  }

  cleanDocument();
})();
''';
  }
}
