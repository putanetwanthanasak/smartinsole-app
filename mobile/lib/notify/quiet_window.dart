import '../ble/packets.dart';

/// Which foot alert notifications may play a sound (BACKLOG 76, user
/// decision 2026-11-02): one posted within [window] of the last one that
/// sounded for the same foot goes on the silent channel instead. It is
/// still posted, so it is still in the tray. The window counts from the
/// last *sounded* notification, so a chain of alerts sounds again once
/// [window] has passed since the first.
///
/// Times are the alerts' own `atMs`, so the decision depends on when the
/// alerts were raised, not on when the plugin got to post them. Kept in
/// memory: after an app restart the next alert sounds.
class NotificationQuietWindow {
  NotificationQuietWindow(this.window);

  final Duration window;
  final _lastSoundAtMs = <FootSide, int>{};

  /// True when a notification for [side] raised at [atMs] may sound; it
  /// then counts as the last sounded one for [side]. False when it falls
  /// within [window] of the last sounded one for [side].
  bool claimSound(FootSide side, int atMs) {
    final last = _lastSoundAtMs[side];
    if (last != null && (atMs - last).abs() < window.inMilliseconds) {
      return false;
    }
    _lastSoundAtMs[side] = atMs;
    return true;
  }
}
