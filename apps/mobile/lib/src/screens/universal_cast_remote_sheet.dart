import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import '../models/cast_device.dart';
import 'cast_remote_sheet.dart' show CastRemoteSheet;
import 'dlna_remote_sheet.dart';
import 'google_cast_remote_sheet.dart';

Future<void> showUniversalCastRemoteSheet(
  BuildContext context,
  StreamFlowController controller,
) async {
  final device = controller.activeDevice;
  final media = controller.activeMedia;
  if (device == null || media == null) return;

  Widget? sheet;
  switch (device.protocol) {
    case CastProtocol.streamFlow:
      final pairingCode = controller.activePairingCode;
      if (pairingCode == null) return;
      sheet = CastRemoteSheet(
        controller: controller,
        device: device,
        media: media,
        pairingCode: pairingCode,
      );
      break;
    case CastProtocol.googleCast:
      sheet = GoogleCastRemoteSheet(
        controller: controller,
        device: device,
        media: media,
      );
      break;
    case CastProtocol.dlna:
      sheet = DlnaRemoteSheet(
        controller: controller,
        device: device,
        media: media,
      );
      break;
    case CastProtocol.airPlay:
      return;
  }

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.82, child: sheet),
  );
}
