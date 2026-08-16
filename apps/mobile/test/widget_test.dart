import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/src/browser/browser_tab_session.dart';

void main() {
  group('Browser address normalization', () {
    test('adds HTTPS to domain input', () {
      expect(
        BrowserTabSession.normalizeAddress('example.com').toString(),
        'https://example.com',
      );
    });

    test('turns plain text into a Google search', () {
      final uri = BrowserTabSession.normalizeAddress('streamflow browser');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/search');
      expect(uri.queryParameters['q'], 'streamflow browser');
    });
  });
}
