import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/browser/ad_blocker.dart';

void main() {
  group('AdBlocker.shouldBlockUrl', () {
    final blocker = AdBlocker();

    test('blocks known ad hosts and subdomains', () {
      expect(blocker.shouldBlockUrl('https://doubleclick.net/ad.js'), isTrue);
      expect(blocker.shouldBlockUrl('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'), isTrue);
      expect(blocker.shouldBlockUrl('https://ads.example.openx.net/banner'), isTrue);
    });

    test('does not block normal site and media URLs', () {
      expect(blocker.shouldBlockUrl('https://example.com/video/master.m3u8'), isFalse);
      expect(blocker.shouldBlockUrl('https://cdn.example.com/movie.mp4'), isFalse);
    });
  });
}
