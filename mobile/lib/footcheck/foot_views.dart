import '../storage/models.dart';

/// Which lens a view starts with (user decision 2026-10-26): soles use the
/// front camera (phone on the floor, screen up), tops the back camera.
enum CameraFacing { front, back }

extension FootViewFacts on FootView {
  bool get isSole => this == FootView.soleLeft || this == FootView.soleRight;

  bool get isLeft => this == FootView.soleLeft || this == FootView.topLeft;

  CameraFacing get autoFacing =>
      isSole ? CameraFacing.front : CameraFacing.back;

  /// File name stem inside a check's folder.
  String get fileStem => switch (this) {
    FootView.soleLeft => 'sole_left',
    FootView.soleRight => 'sole_right',
    FootView.topLeft => 'top_left',
    FootView.topRight => 'top_right',
  };
}

extension CameraFacingFlip on CameraFacing {
  CameraFacing get other =>
      this == CameraFacing.front ? CameraFacing.back : CameraFacing.front;
}
