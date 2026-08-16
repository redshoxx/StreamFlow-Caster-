import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AdBlocker {
  AdBlocker([this._preferences]);

  static const _enabledKey = 'streamflow.adblock.enabled.v2';

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
    'adsafeprotected.com',
    'moatads.com',
    'yieldmo.com',
    'bidswitch.net',
    'lijit.com',
    'sharethrough.com',
    'teads.tv',
    'adform.net',
    'adform.com',
    'serving-sys.com',
    'zedo.com',
    'revcontent.com',
    'mgid.com',
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'onclickads.net',
    'exoclick.com',
    'juicyads.com',
    'hilltopads.net',
    'trafficjunky.net',
    'admaven.com',
    'adsterra.com',
    'monetag.com',
    'clickadu.com',
    'pushengage.com',
    'pushwoosh.com',
    'wonderpush.com',
    'onesignal.com',
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
    'ins.adsbygoogle',
    '.adsbygoogle',
    '[data-ad-slot]',
    '[data-ad-client]',
    '[data-google-query-id]',
    '[id^="google_ads_"]',
    '[id^="div-gpt-ad"]',
    '[class~="advertisement"]',
    '[class~="advertising"]',
    '[class~="sponsored"]',
    '[id^="ad-"]',
    '[id^="ad_"]',
    '[class^="ad-container"]',
    '[class^="ad_container"]',
    '[class^="ad-wrapper"]',
    '[class^="ad_wrapper"]',
    'iframe[src*="doubleclick.net"]',
    'iframe[src*="googlesyndication.com"]',
    'iframe[src*="amazon-adsystem.com"]',
    '#onesignal-slidedown-container',
    '.onesignal-slidedown-container',
    '[id*="pushengage"]',
    '[class*="pushengage"]',
    '[class*="webpush"]',
    '[class*="notification-prompt"]',
    '[id*="notification-prompt"]'
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
        if (isBlocked(element.getAttribute('src'))) removed += removeElement(element);
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
        if (isBlocked(element.getAttribute('src'))) removed += removeElement(element);
      });
    } catch (_) {}
    report(removed);
  };

  if (!window.__streamFlowPrivacyBlockInstalled) {
    window.__streamFlowPrivacyBlockInstalled = true;

    try {
      if (window.Notification && Notification.requestPermission) {
        Notification.requestPermission = () => Promise.resolve('denied');
      }
    } catch (_) {}

    try {
      if (window.PushManager && PushManager.prototype && PushManager.prototype.subscribe) {
        PushManager.prototype.subscribe = () => Promise.reject(
          new DOMException('Web push is disabled by StreamFlow', 'NotAllowedError')
        );
      }
    } catch (_) {}

    try {
      if (window.ServiceWorkerRegistration && ServiceWorkerRegistration.prototype.showNotification) {
        ServiceWorkerRegistration.prototype.showNotification = () => Promise.reject(
          new DOMException('Web notifications are disabled by StreamFlow', 'NotAllowedError')
        );
      }
    } catch (_) {}

    const originalOpen = window.open ? window.open.bind(window) : null;
    if (originalOpen) {
      window.open = (url, ...args) => {
        if (!url || isBlocked(url)) {
          report(1);
          return null;
        }
        let userInitiated = false;
        try { userInitiated = !!(navigator.userActivation && navigator.userActivation.isActive); } catch (_) {}
        if (!userInitiated) {
          report(1);
          return null;
        }
        try {
          const target = new URL(url, document.baseURI);
          window.location.assign(target.href);
          return null;
        } catch (_) {
          return originalOpen(url, ...args);
        }
      };
    }

    document.addEventListener('click', (event) => {
      try {
        const anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
        if (!anchor) return;
        const href = anchor.href;
        if (isBlocked(href)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          report(1);
          return;
        }
        if (anchor.target && anchor.target.toLowerCase() === '_blank') {
          anchor.target = '_self';
        }
      } catch (_) {}
    }, true);

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
      const pendingNodes = new Set();
      let scheduled = false;
      const flush = () => {
        scheduled = false;
        let removed = 0;
        pendingNodes.forEach((node) => { removed += cleanNode(node); });
        pendingNodes.clear();
        report(removed);
      };
      const scheduleFlush = () => {
        if (scheduled) return;
        scheduled = true;
        if (window.requestAnimationFrame) window.requestAnimationFrame(flush);
        else window.setTimeout(flush, 16);
      };
      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          mutation.addedNodes.forEach((node) => {
            if (node instanceof Element) pendingNodes.add(node);
          });
        }
        if (pendingNodes.size) scheduleFlush();
      });
      observer.observe(document.documentElement, {childList: true, subtree: true});
    }
  }

  cleanDocument();
})();
''';
  }
}
