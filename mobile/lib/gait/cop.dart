import 'dart:ui';

import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../device/foot_sample.dart';
import '../rules/step_detector.dart';
import 'gait_timing.dart';

/// The centre-of-pressure path of each foot's newest walking step
/// (DESIGN-SPEC §8.3 details, "เส้นทางของแรงกดในก้าวล่าสุด (CoP)").
///
/// Each sample's CoP is the zone positions weighted by their kPa
/// (Σ kPa·position / Σ kPa), in the foot drawing's view-box units. The
/// positions are the placeholder layout's until `shared/sensor_layout.json`
/// exists (DESIGN-SPEC §14 decision 3), so the path shows the order the
/// zones load in, not millimetres.
class CopTracker {
  CopTracker({required this.keepMs, this.layout = footLayout});

  /// How much of each foot's recent samples is kept: longer than a stance
  /// can last, so a completed step's samples are all still here.
  final double keepMs;
  final FootLayout layout;

  final _samples = {for (final side in FootSide.values) side: <FootSample>[]};
  final _session = <FootSide, int>{};
  final _paths = <FootSide, List<Offset>>{};

  void add(FootBatch b) {
    final buf = _samples[b.side]!;
    if (_session[b.side] != b.session) {
      buf.clear();
      _paths.remove(b.side);
    }
    _session[b.side] = b.session;
    buf.addAll(b.samples);
    if (buf.isEmpty) return;
    final keepFrom = buf.last.unixMs - keepMs;
    buf.removeWhere((s) => s.unixMs < keepFrom);
  }

  /// [step] completed: its samples become the foot's newest path.
  void onStep(Step step) {
    final points = <Offset>[];
    for (final s in _samples[step.side]!) {
      if (s.unixMs < step.startMs || s.unixMs >= step.endMs) continue;
      final p = copOf(s.fsrKpa, step.side);
      if (p != null) points.add(p);
    }
    if (points.isEmpty) return;
    _paths[step.side] = _thin(points);
  }

  /// The newest step's path of [side], or null before its first step in
  /// this connection.
  List<Offset>? pathOf(FootSide side) => _paths[side];

  /// One sample's CoP, or null when nothing is loaded.
  Offset? copOf(List<double> kpa, FootSide side) {
    var sum = 0.0;
    var x = 0.0;
    var y = 0.0;
    for (var c = 0; c < kpa.length && c < layout.zones.length; c++) {
      final k = kpa[c];
      if (k <= 0) continue;
      final p = layout.zones[c].position(side);
      sum += k;
      x += k * p.dx;
      y += k * p.dy;
    }
    return sum <= 0 ? null : Offset(x / sum, y / sum);
  }

  void clear() {
    for (final buf in _samples.values) {
      buf.clear();
    }
    _paths.clear();
    _session.clear();
  }

  static List<Offset> _thin(List<Offset> points) {
    if (points.length <= copMaxPoints) return List.unmodifiable(points);
    final step = points.length / copMaxPoints;
    return List.unmodifiable([
      for (var i = 0; i < copMaxPoints; i++) points[(i * step).floor()],
      points.last,
    ]);
  }
}
