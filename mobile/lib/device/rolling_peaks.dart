import 'display_snapshot.dart';
import 'foot_sample.dart';

/// The foot maps' peak window: a dot shows the highest kPa of the last
/// 2 s, the same window as the web app's heatmap (report 003). Display
/// only, not a threshold. The alert engine keeps the same window, so the
/// map stored with a pressure alert is the map Home showed.
const mapPeakWindowMs = 2000;

/// The kPa per zone a foot map shows for [f]: the windowed peaks
/// ([windowPeaks], from a [RollingPeaks] of [mapPeakWindowMs]), the
/// newest sample while that window is still empty, or null when the foot
/// is not usable. Home and the alert engine both use this, so they never
/// disagree.
List<double>? mapPeaksOf(FootView f, List<double>? windowPeaks) =>
    f.usable ? (windowPeaks ?? f.kpa) : null;

/// Highest kPa per FSR channel over the last [windowMs] of one foot's
/// samples, fed from the 50 Hz path ([DeviceManager.batches]) and read on
/// the 10 Hz display path (rule 10). Taking the peak from the full-rate
/// stream matters: the 10 Hz snapshot keeps one sample in five and would
/// miss most heel-strike peaks.
///
/// The window ends at this foot's newest sample time, so it does not
/// depend on the phone clock; whether the foot is usable at all is the
/// caller's question (read-time staleness, rule 2). Samples are kept in
/// [bucketMs] buckets, so memory is fixed whatever the rate.
class RollingPeaks {
  RollingPeaks({required this.windowMs, this.bucketMs = 100})
    : assert(windowMs % bucketMs == 0);

  final int windowMs;
  final int bucketMs;

  final _buckets = <(int, List<double>)>[];
  int? _session;

  /// Adds one batch. A new connection session starts an empty window.
  void add(FootBatch batch) {
    if (batch.session != _session) {
      _session = batch.session;
      _buckets.clear();
    }
    for (final s in batch.samples) {
      _addSample(s.unixMs, s.fsrKpa);
    }
  }

  void _addSample(double unixMs, List<double> kpa) {
    final index = unixMs ~/ bucketMs;
    if (_buckets.isNotEmpty && _buckets.last.$1 == index) {
      final peaks = _buckets.last.$2;
      for (var c = 0; c < kpa.length && c < peaks.length; c++) {
        if (kpa[c] > peaks[c]) peaks[c] = kpa[c];
      }
      return;
    }
    // A sample older than the newest bucket (it cannot happen with a
    // monotonic DeviceClock) is folded into the newest bucket's window.
    if (_buckets.isNotEmpty && index < _buckets.last.$1) {
      _addSample(_buckets.last.$1 * bucketMs.toDouble(), kpa);
      return;
    }
    _buckets.add((index, List.of(kpa)));
    final oldest = index - windowMs ~/ bucketMs;
    _buckets.removeWhere((b) => b.$1 <= oldest);
  }

  /// Highest kPa per channel in the window, or null when empty.
  List<double>? channelPeaks() {
    if (_buckets.isEmpty) return null;
    final out = List.of(_buckets.first.$2);
    for (final (_, peaks) in _buckets.skip(1)) {
      for (var c = 0; c < out.length && c < peaks.length; c++) {
        if (peaks[c] > out[c]) out[c] = peaks[c];
      }
    }
    return out;
  }

  /// Highest kPa of any channel in the window, or null when empty.
  double? footPeak() {
    final peaks = channelPeaks();
    if (peaks == null) return null;
    return peaks.fold<double>(0, (m, v) => v > m ? v : m);
  }

  void clear() {
    _buckets.clear();
    _session = null;
  }
}
