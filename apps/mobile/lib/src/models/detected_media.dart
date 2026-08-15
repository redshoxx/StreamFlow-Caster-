enum MediaKind { hls, dash, video, audio, unknown }

class DetectedMedia {
  const DetectedMedia({
    required this.url,
    required this.kind,
    this.label,
    this.mimeType,
  });

  final Uri url;
  final MediaKind kind;
  final String? label;
  final String? mimeType;

  String get displayName => label?.trim().isNotEmpty == true
      ? label!.trim()
      : url.pathSegments.isNotEmpty
          ? url.pathSegments.last
          : url.host;

  @override
  bool operator ==(Object other) =>
      other is DetectedMedia && other.url.toString() == url.toString();

  @override
  int get hashCode => url.toString().hashCode;
}
