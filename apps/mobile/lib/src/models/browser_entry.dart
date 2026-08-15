class BrowserEntry {
  const BrowserEntry({
    required this.url,
    required this.title,
    required this.timestamp,
  });

  final Uri url;
  final String title;
  final DateTime timestamp;

  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return url.host.isNotEmpty ? url.host : url.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url.toString(),
        'title': title,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };

  static BrowserEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final url = Uri.tryParse(raw['url']?.toString() ?? '');
    final timestamp = DateTime.tryParse(raw['timestamp']?.toString() ?? '');
    if (url == null || timestamp == null || !_supportedScheme(url)) return null;

    return BrowserEntry(
      url: url,
      title: raw['title']?.toString() ?? '',
      timestamp: timestamp.toLocal(),
    );
  }

  static bool _supportedScheme(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';
}
