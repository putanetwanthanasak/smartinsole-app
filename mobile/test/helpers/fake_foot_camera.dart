import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:smartinsole/footcheck/foot_camera.dart';
import 'package:smartinsole/footcheck/foot_views.dart';
import 'package:smartinsole/ui/theme/colors.dart';

/// In-memory [FootCamera]: a flat "preview" and small generated JPEGs.
class FakeFootCamera implements FootCamera {
  FakeFootCamera({this.deny = false, this.fail = false});

  bool deny;
  bool fail;

  /// With [deny]: whether Android would still show the dialog.
  bool askAgain = true;
  final opened = <CameraFacing>[];
  var shots = 0;
  var settingsOpened = 0;
  CameraFacing? current;

  /// When set, [open] waits for it (an open still in progress).
  Completer<void>? gate;

  @override
  Future<CameraFacing> open(CameraFacing facing) async {
    await gate?.future;
    if (deny) {
      throw CameraUnavailable(permissionDenied: true, askAgain: askAgain);
    }
    if (fail) throw const CameraUnavailable(permissionDenied: false);
    opened.add(facing);
    return current = facing;
  }

  @override
  Widget buildPreview() => const ColoredBox(
    key: ValueKey('fake-preview'),
    color: CameraColors.slotDone,
  );

  @override
  Future<Uint8List> take() async {
    shots++;
    return jpegOf(shots);
  }

  @override
  Future<void> close() async => current = null;

  @override
  Future<void> openSettings() async => settingsOpened++;

  /// A small portrait JPEG whose colour changes with [n].
  static Uint8List jpegOf(int n) {
    final image = img.Image(width: 90, height: 160);
    img.fill(image, color: img.ColorRgb8(40 * n % 255, 120, 160));
    return img.encodeJpg(image);
  }
}
