import 'dart:async';
import 'dart:io';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../models/cast_device.dart';
import '../models/detected_media.dart';

class GoogleCastService {
  GoogleCastService._();

  static final GoogleCastService instance = GoogleCastService._();

  final _controller = StreamController<List<CastDevice>>.broadcast();
  final Map<String, GoogleCastDevice> _nativeDevices = {};
  StreamSubscription<List<GoogleCastDevice>>? _subscription;
  bool _initialized = false;

  Stream<List<CastDevice>> get devices => _controller.stream;

  Future<void> initialize() async {
    if (_initialized || !(Platform.isAndroid || Platform.isIOS)) return;

    const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
    final GoogleCastOptions options;
    if (Platform.isIOS) {
      options = IOSGoogleCastOptions(
        GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
        stopCastingOnAppTerminated: false,
      );
    } else {
      options = GoogleCastOptionsAndroid(
        appId: appId,
        stopCastingOnAppTerminated: false,
      );
    }

    GoogleCastContext.instance.setSharedInstanceWithOptions(options);
    _subscription ??= GoogleCastDiscoveryManager.instance.devicesStream.listen(
      _onDevices,
      onError: (_) {},
    );
    GoogleCastDiscoveryManager.instance.startDiscovery();
    _initialized = true;
  }

  void _onDevices(List<GoogleCastDevice> devices) {
    _nativeDevices
      ..clear()
      ..addEntries(devices.map((device) => MapEntry(device.deviceID, device)));

    final mapped = devices
        .map(
          (device) => CastDevice(
            id: device.deviceID,
            name: device.friendlyName,
            protocol: CastProtocol.googleCast,
            modelName: device.modelName,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!_controller.isClosed) _controller.add(List.unmodifiable(mapped));
  }

  Future<void> load(CastDevice device, DetectedMedia media) async {
    await initialize();
    final native = _nativeDevices[device.id];
    if (native == null) {
      throw StateError('Google Cast device is no longer available.');
    }

    await GoogleCastSessionManager.instance.startSessionWithDevice(native);
    await GoogleCastRemoteMediaClient.instance.loadMedia(
      GoogleCastMediaInformation(
        contentId: media.url.toString(),
        contentUrl: media.url,
        streamType: CastMediaStreamType.BUFFERED,
        contentType: _contentType(media),
      ),
      autoPlay: true,
      playPosition: Duration.zero,
      playbackRate: 1.0,
    );
  }

  GoggleCastMediaStatus? get mediaStatus =>
      GoogleCastRemoteMediaClient.instance.mediaStatus;

  Duration get playerPosition =>
      GoogleCastRemoteMediaClient.instance.playerPosition;

  Stream<GoggleCastMediaStatus?> get mediaStatusStream =>
      GoogleCastRemoteMediaClient.instance.mediaStatusStream;

  Future<void> play() async {
    await GoogleCastRemoteMediaClient.instance.play();
  }

  Future<void> pause() async {
    await GoogleCastRemoteMediaClient.instance.pause();
  }

  Future<void> stop() async {
    await GoogleCastRemoteMediaClient.instance.stop();
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
  }

  Future<void> seek(Duration position) async {
    await GoogleCastRemoteMediaClient.instance.seek(
      GoogleCastMediaSeekOption(position: position),
    );
  }

  String _contentType(DetectedMedia media) {
    final explicit = media.mimeType?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return switch (media.kind) {
      MediaKind.hls => 'application/x-mpegURL',
      MediaKind.dash => 'application/dash+xml',
      MediaKind.audio => 'audio/mpeg',
      MediaKind.video => 'video/mp4',
      MediaKind.unknown => 'video/mp4',
    };
  }

  Future<void> dispose() async {
    GoogleCastDiscoveryManager.instance.stopDiscovery();
    await _subscription?.cancel();
    _subscription = null;
    _nativeDevices.clear();
    if (!_controller.isClosed) await _controller.close();
  }
}
