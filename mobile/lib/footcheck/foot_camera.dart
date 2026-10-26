import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'foot_views.dart';

/// The camera seen by the Capture screen. Only `plugin_foot_camera.dart`
/// imports the camera plugin; tests and goldens use [FakeFootCamera].
abstract interface class FootCamera {
  /// Opens [facing], or the other lens when the phone has only one.
  /// Returns the lens actually opened. Throws [CameraUnavailable].
  Future<CameraFacing> open(CameraFacing facing);

  /// The live preview, filling its parent (cover). A front preview is
  /// mirrored, like a mirror (decision 1).
  Widget buildPreview();

  /// Takes one photo and returns its JPEG bytes as the camera wrote them.
  /// The plugin's temporary file (app cache) is deleted before this
  /// returns: nothing is left outside the foot-photo folder (rule 15).
  Future<Uint8List> take();

  Future<void> close();

  /// Opens the app's system settings page (camera access refused).
  Future<void> openSettings();
}

class CameraUnavailable implements Exception {
  const CameraUnavailable({
    required this.permissionDenied,
    this.askAgain = true,
    this.detail,
  });

  /// The user refused camera access (the draft panel's allow button).
  final bool permissionDenied;

  /// Android still shows the permission dialog; false once it no longer
  /// does ("don't ask again"), when only the app's settings can allow it.
  final bool askAgain;
  final String? detail;

  @override
  String toString() =>
      'CameraUnavailable(permissionDenied: $permissionDenied, '
      'askAgain: $askAgain, $detail)';
}
