/// The two device-wide commands (contract §3.4) the Researcher screen sends
/// (S8B). Both act on the whole insole, not on one connection (BACKLOG 17,
/// 21), so they go only through `InsoleCommands` (`lib/device/`), which
/// refuses them while a research capture session is open.
abstract interface class InsoleControl {
  /// True while this foot streams, so a command can be written.
  bool get canCommand;

  /// `TARE`: the insole flags its packets as calibrating while it measures
  /// the zero point, then the app re-reads the calibration (BACKLOG 23).
  Future<void> sendTare();

  /// `REBOOT`: the link drops, and the foot reconnects on its own.
  Future<void> sendReboot();
}
