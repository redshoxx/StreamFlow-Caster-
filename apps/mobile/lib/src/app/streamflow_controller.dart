import 'package:flutter/foundation.dart';

import '../models/cast_device.dart';
import '../models/detected_media.dart';

class StreamFlowController extends ChangeNotifier {
  final List<DetectedMedia> _detectedMedia = <DetectedMedia>[];

  List<DetectedMedia> get detectedMedia => List.unmodifiable(_detectedMedia);

  CastDevice? _preferredDevice;
  CastDevice? get preferredDevice => _preferredDevice;

  CastDevice? _activeDevice;
  CastDevice? get activeDevice => _activeDevice;

  DetectedMedia? _activeMedia;
  DetectedMedia? get activeMedia => _activeMedia;

  bool get isCasting => _activeDevice != null && _activeMedia != null;

  void addDetectedMedia(DetectedMedia media) {
    if (_detectedMedia.contains(media)) return;
    _detectedMedia.insert(0, media);
    notifyListeners();
  }

  void clearDetectedMedia() {
    if (_detectedMedia.isEmpty) return;
    _detectedMedia.clear();
    notifyListeners();
  }

  void removeDetectedMedia(DetectedMedia media) {
    if (_detectedMedia.remove(media)) notifyListeners();
  }

  void setPreferredDevice(CastDevice device) {
    _preferredDevice = device;
    notifyListeners();
  }

  void startCasting(CastDevice device, DetectedMedia media) {
    _preferredDevice = device;
    _activeDevice = device;
    _activeMedia = media;
    notifyListeners();
  }

  void endCasting() {
    if (!isCasting) return;
    _activeDevice = null;
    _activeMedia = null;
    notifyListeners();
  }
}
