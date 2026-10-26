import 'package:flutter/widgets.dart';

/// Named routes for screens pushed on top of the tab shell.
abstract final class Routes {
  static const shell = '/';
  static const connection = '/connection';
  static const settings = '/settings';

  /// Alert detail; the argument is the alert's id (`int`).
  static const alertDetail = '/alert';

  /// Foot check › Something found; the argument is the foot check's id
  /// (`int`).
  static const footCheckFound = '/foot-check-found';

  /// Foot check › Capture (full screen, camera colours).
  static const footCheckCapture = '/foot-check/capture';

  /// Foot check › Compare & answer.
  static const footCheckCompare = '/foot-check/compare';

  /// Photo history ("ดูรูปที่บันทึกไว้").
  static const footCheckPhotos = '/foot-check/photos';

  /// One photo full screen; the argument is a `PhotoViewerArgs`.
  static const footCheckPhoto = '/foot-check/photo';

  /// Researcher (S8B): Settings › hold "ส่วนผู้วิจัย" 2 s.
  static const researcher = '/researcher';

  /// Research capture (S4C): researcher-only, from Researcher.
  static const capture = '/capture';

  /// Diagnostics, the S3A BLE debug screen: only from Researcher (S8B).
  static const bleDebug = '/debug-ble';
}

/// The app's root navigator, so a tapped reminder can return to the tabs.
final appNavigatorKey = GlobalKey<NavigatorState>();
