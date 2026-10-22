import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// What the researcher must notice with the phone in a pocket.
enum Cue {
  /// Practice started (not recorded): two low beeps, two short buzzes.
  practice('cue_practice.wav', [0, 120, 120, 120]),

  /// Recording started: one high beep, one buzz.
  start('cue_start.wav', [0, 400]),

  /// [CaptureTimings.endWarning] left: two beeps, two buzzes.
  warning('cue_warning.wav', [0, 250, 150, 250]),

  /// Recording ended: three beeps, two long buzzes.
  end('cue_end.wav', [0, 800, 200, 800]),

  /// A foot's link is down: repeated while it stays down.
  linkLost('cue_link_lost.wav', [0, 150, 100, 150, 100, 150, 100, 150]),

  /// The foot is streaming again.
  linkBack('cue_start.wav', [0, 150]);

  const Cue(this.sound, this.vibration);

  /// Under `assets/sounds/` (made by `tool/make_cues.py`).
  final String sound;

  /// Off/on milliseconds, starting with a pause.
  final List<int> vibration;
}

/// Plays cues. Tests use a fake that records them.
abstract interface class CaptureCues {
  void play(Cue cue);
  void dispose();
}

/// Sound through the media stream (it plays in silent mode too) plus a
/// vibration pattern. A failing plugin never stops a recording: a cue is
/// best-effort, the data path doesn't depend on it.
class DeviceCues implements CaptureCues {
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  @override
  void play(Cue cue) {
    _player
        .play(AssetSource('sounds/${cue.sound}'), volume: 1)
        .catchError((Object _) {});
    Vibration.vibrate(pattern: cue.vibration).catchError((Object _) {});
  }

  @override
  void dispose() => _player.dispose();
}
