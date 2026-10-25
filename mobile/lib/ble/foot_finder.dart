import 'dart:async';

import 'ble_data_source.dart';
import 'ble_hub.dart';
import 'foot_connector.dart';
import 'link_state.dart';
import 'packets.dart';

/// Finds and connects one foot's insole without a scan list (S8B), so a
/// patient can connect both feet from the Connection screen alone.
///
/// It is layered on [BleDataSource.connectTo]; the connect sequence and its
/// rule 8 / rule 9 checks are not changed. For each insole that advertises
/// the service and that the other foot has not claimed, it runs the normal
/// sequence. The status read decides the side:
/// - this foot: it streams, and the insole is remembered ([remember]) so
///   the app reconnects it at start ([autoConnect]);
/// - the other foot: the source rejects it (rule 8, a [LinkProblem] with no
///   START), and the finder tries the next candidate;
/// - this foot but unusable (MTU too small, calibration rejected): it stays
///   bound, and the screen shows "connected, no data".
///
/// After [window] with no match it ends as [FinderNotFound], or as
/// [FinderWrongSide] if an insole of the other foot answered. Once one has,
/// it ends after [wrongSideGrace] unless another candidate turns up (with
/// both insoles on, the other foot's may simply be seen first).
///
/// It also follows every automatic reconnect of this foot (at app start and
/// after a lost link) in [reconnects] and in the BLE event log, so S9 can
/// measure them (BACKLOG 45).
class FootFinder implements FootConnector {
  FootFinder({
    required this.source,
    required this.hub,
    required this.now,
    required this.recall,
    required this.remember,
    this.window = defaultWindow,
    this.wrongSideGrace = defaultWrongSideGrace,
  }) {
    _linkSub = source.states.listen(_onLink);
    _readinessSub = hub.readinessChanges.listen(_onReadiness);
  }

  /// User decision 3A (S8B).
  static const defaultWindow = Duration(seconds: 20);
  static const defaultWrongSideGrace = Duration(seconds: 3);

  /// How long [find] waits for a permission check already in flight.
  static const readinessWait = Duration(seconds: 3);

  final BleDataSource source;
  final BleHub hub;
  final DateTime Function() now;
  final Duration window;
  final Duration wrongSideGrace;

  /// The insole remembered for this foot, and how to change it.
  final String? Function() recall;
  final Future<void> Function(String? deviceId) remember;

  final reconnects = ReconnectStats();

  late final StreamSubscription<LinkState> _linkSub;
  late final StreamSubscription<BleReadiness> _readinessSub;

  FinderState _state = const FinderIdle();
  final _states = StreamController<FinderState>.broadcast();

  String? _trying;
  final _tried = <String>{};
  final _wrong = <String, FootSide>{};
  bool _windowOver = false;
  bool _graceOver = false;
  Timer? _windowTimer;
  Timer? _graceTimer;
  StreamSubscription<SeenInsole>? _sightingSub;
  LinkState _lastLink = const LinkIdle();

  @override
  FootSide get side => source.side;

  @override
  FinderState get state => _state;

  @override
  Stream<FinderState> get states => _states.stream;

  bool get _finding => _state is FinderSearching;

  /// At app start: reconnects the remembered insole, if there is one. The
  /// source keeps searching for it until it advertises.
  Future<void> autoConnect() async {
    final id = recall();
    if (id == null || _finding) return;
    final s = source.state;
    if (s is! LinkIdle && s is! LinkProblem) return;
    await hub.start();
    _begin('app start', id);
    await source.connectTo(id);
  }

  @override
  Future<void> find() async {
    if (_finding) return;
    await hub.start();
    if (hub.readiness == BleReadiness.checking) {
      // Another caller started the hub and its permission check is still
      // running.
      await hub.readinessChanges
          .firstWhere((r) => r != BleReadiness.checking)
          .timeout(readinessWait, onTimeout: () => hub.readiness);
    }
    if (hub.readiness == BleReadiness.needsPermission) {
      await hub.requestPermission();
    }
    if (hub.readiness != BleReadiness.ready) {
      hub.log.add(
        'find: Bluetooth not ready (${hub.readiness.name})',
        side: side,
      );
      return;
    }
    final s = source.state;
    if (s is! LinkIdle && s is! LinkProblem) await source.disconnect();
    _tried.clear();
    _wrong.clear();
    _windowOver = false;
    _graceOver = false;
    _set(const FinderSearching());
    hub.log.add('finding an insole for this foot', side: side);
    hub.acquireScan(this);
    _sightingSub = hub.sightings.listen((s) => _consider(s.deviceId));
    _windowTimer = Timer(window, () {
      _windowOver = true;
      _maybeFinish();
    });
    _considerSeen();
  }

  @override
  Future<void> stop() async {
    if (_finding) {
      _stopFinding();
      _set(const FinderIdle());
      hub.log.add('finding stopped by user', side: side);
    } else if (_state is! FinderIdle) {
      _set(const FinderIdle());
    }
    await source.disconnect();
  }

  @override
  Future<void> reconnect() async {
    await stop();
    await find();
  }

  @override
  Future<void> disconnect() async {
    await stop();
    await remember(null);
    hub.log.add('insole forgotten', side: side);
  }

  void dispose() {
    _stopFinding();
    _linkSub.cancel();
    _readinessSub.cancel();
    _states.close();
  }

  // --- Finding --------------------------------------------------------------

  void _considerSeen() {
    for (final s in hub.seen) {
      _consider(s.deviceId);
    }
  }

  void _consider(String id) {
    if (!_finding || _trying != null || _windowOver) return;
    if (_tried.contains(id)) return;
    final holder = hub.claimedBy(id);
    if (holder != null && holder != side) return;
    if (!hub.seenRecently(id)) return;
    _trying = id;
    _tried.add(id);
    hub.log.add('trying $id', side: side);
    unawaited(source.connectTo(id));
  }

  /// The candidate's outcome, from the foot's link state.
  void _onCandidate(String id, LinkState s) {
    switch (s) {
      case LinkStreaming():
        _found(id);
      case LinkProblem(kind: ProblemKind.wrongSide, :final reportedSide):
        _trying = null;
        _wrong[id] = reportedSide!;
        hub.log.add(
          '$id is the ${reportedSide.name} insole; looking further',
          side: side,
        );
        _graceTimer ??= Timer(wrongSideGrace, () {
          _graceOver = true;
          _maybeFinish();
        });
        _considerSeen();
        _maybeFinish();
      case LinkProblem(kind: ProblemKind.mtuTooSmall) ||
          LinkProblem(kind: ProblemKind.calibrationInvalid):
        // This foot's insole, but it can't stream: keep it, and the screen
        // shows "connected, no data" (user decision 5A).
        _found(id);
      case LinkProblem():
        // Not an insole after all, or held by the other foot.
        _trying = null;
        _considerSeen();
        _maybeFinish();
      case LinkRetryWait():
        // A failed attempt (e.g. GATT 133): stop retrying this one here, so
        // other candidates get their turn; it can be tried again when it
        // next advertises.
        _trying = null;
        _tried.remove(id);
        unawaited(source.disconnect());
        _maybeFinish();
      case LinkIdle() || LinkBlocked() || LinkSearching() || LinkConnecting():
        break;
    }
  }

  void _found(String id) {
    _stopFinding();
    _set(const FinderIdle());
    hub.log.add('found this foot\'s insole $id', side: side);
    unawaited(remember(id));
  }

  void _maybeFinish() {
    if (!_finding || _trying != null) return;
    if (_windowOver || (_graceOver && _wrong.isNotEmpty)) {
      final reported = _wrong.values.isEmpty ? null : _wrong.values.first;
      _stopFinding();
      if (reported != null) {
        hub.log.add('find ended: only a ${reported.name} insole', side: side);
        _set(FinderWrongSide(reported));
      } else {
        hub.log.add('find ended: no insole found', side: side);
        _set(const FinderNotFound());
      }
    }
  }

  void _stopFinding() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _sightingSub?.cancel();
    _sightingSub = null;
    _trying = null;
    hub.releaseScan(this);
  }

  void _onReadiness(BleReadiness r) {
    if (r == BleReadiness.ready || !_finding) return;
    // Bluetooth went off (or permission was revoked) mid-search: the
    // screen shows the Bluetooth panel; the user searches again after.
    _stopFinding();
    hub.log.add('finding stopped: ${r.name}', side: side);
    _set(const FinderIdle());
    unawaited(source.disconnect());
  }

  void _set(FinderState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  // --- Link states: candidates and the reconnect record --------------------

  void _onLink(LinkState s) {
    final prev = _lastLink;
    _lastLink = s;
    final id = _trying;
    if (_finding && id != null && s.deviceId == id) _onCandidate(id, s);
    _trackReconnect(prev, s);
  }

  void _begin(String reason, String deviceId) {
    final n = reconnects._begin(reason, deviceId, now());
    hub.log.add('auto-reconnect #$n ($reason) to $deviceId', side: side);
  }

  void _trackReconnect(LinkState prev, LinkState s) {
    if (prev is LinkStreaming && s is! LinkStreaming && s is! LinkIdle) {
      _begin('link lost', prev.deviceId);
    }
    final r = reconnects;
    if (!r.pending) return;
    final n = r.attempts;
    switch (s) {
      case LinkStreaming():
        final took = r._end('streaming', now(), succeeded: true);
        hub.log.add(
          'auto-reconnect #$n → streaming after '
          '${(took.inMilliseconds / 1000).toStringAsFixed(1)} s '
          '(${r.lastFailedTries} failed tries)',
          side: side,
        );
      case LinkRetryWait(:final attempt, :final lastError):
        r._tryFailed();
        hub.log.add(
          'auto-reconnect #$n: try $attempt failed: $lastError',
          side: side,
        );
      case LinkProblem(:final kind):
        r._end('failed: ${kind.name}', now());
        hub.log.add('auto-reconnect #$n → failed: ${kind.name}', side: side);
      case LinkIdle():
        r._end('cancelled', now());
        hub.log.add('auto-reconnect #$n → cancelled', side: side);
      case LinkBlocked(:final reason) when prev is! LinkBlocked:
        hub.log.add('auto-reconnect #$n: waiting (${reason.name})', side: side);
      case LinkBlocked() || LinkSearching() || LinkConnecting():
        break;
    }
  }
}

/// Automatic reconnects of one foot (S8B; BACKLOG 45): at app start, and
/// after a streaming link was lost. Shown on Diagnostics.
class ReconnectStats {
  /// The most recent ones kept in [history].
  static const historyLength = 30;

  int attempts = 0;
  int succeeded = 0;

  /// Failed connect tries inside the attempt in progress.
  int _tries = 0;
  int lastFailedTries = 0;

  String? _reason;
  DateTime? _startedAt;
  Duration? lastDuration;
  String? lastOutcome;
  final history = <ReconnectRecord>[];

  bool get pending => _startedAt != null;

  /// When the attempt in progress began, and why.
  DateTime? get startedAt => _startedAt;
  String? get reason => _reason;

  int _begin(String reason, String deviceId, DateTime at) {
    attempts++;
    _reason = reason;
    _startedAt = at;
    _tries = 0;
    return attempts;
  }

  void _tryFailed() => _tries++;

  Duration _end(String outcome, DateTime at, {bool succeeded = false}) {
    final took = at.difference(_startedAt!);
    if (succeeded) this.succeeded++;
    lastDuration = took;
    lastOutcome = outcome;
    lastFailedTries = _tries;
    history.add(
      ReconnectRecord(
        number: attempts,
        reason: _reason!,
        startedAt: _startedAt!,
        took: took,
        outcome: outcome,
        failedTries: _tries,
      ),
    );
    if (history.length > historyLength) history.removeAt(0);
    _startedAt = null;
    _reason = null;
    return took;
  }
}

class ReconnectRecord {
  const ReconnectRecord({
    required this.number,
    required this.reason,
    required this.startedAt,
    required this.took,
    required this.outcome,
    required this.failedTries,
  });

  final int number;
  final String reason;
  final DateTime startedAt;
  final Duration took;
  final String outcome;
  final int failedTries;

  @override
  String toString() {
    final t = startedAt.toIso8601String().substring(11, 19);
    return '#$number $t $reason → $outcome in '
        '${(took.inMilliseconds / 1000).toStringAsFixed(1)} s, '
        '$failedTries failed tries';
  }
}
