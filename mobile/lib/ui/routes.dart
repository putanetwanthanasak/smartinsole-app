/// Named routes for screens pushed on top of the tab shell.
abstract final class Routes {
  static const shell = '/';
  static const connection = '/connection';
  static const settings = '/settings';

  /// Research capture (S4C): researcher-only, from Settings.
  static const capture = '/capture';

  /// Temporary BLE debug screen (S3A); hidden in S8B.
  static const bleDebug = '/debug-ble';
}
