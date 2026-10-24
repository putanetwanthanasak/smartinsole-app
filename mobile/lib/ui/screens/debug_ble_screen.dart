import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/ble_data_source.dart';
import '../../ble/ble_hub.dart';
import '../../ble/ble_providers.dart';
import '../../ble/link_state.dart';
import '../../ble/link_stats.dart';
import '../../ble/packets.dart';
import '../../device/device_manager.dart';
import '../../device/device_providers.dart';
import '../../device/timing_check.dart';
import '../../storage/storage_providers.dart';
import '../../storage/temperature_repository.dart';
import '../clock.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/app_back_button.dart';
import '../widgets/placeholder_body.dart';

/// Temporary developer screen for S3A: scan, bind each foot, and watch both
/// links (state, MTU, counters, event log). Labels are technical English;
/// problem messages are Thai because their wording carries over to the
/// Connection screen. Reached from Settings; hidden in S8B.
class DebugBleScreen extends ConsumerStatefulWidget {
  const DebugBleScreen({super.key});

  /// How long the "Scan" button keeps the scan running.
  static const manualScan = Duration(seconds: 20);

  /// Display refresh for ages and rates. No data logic depends on it.
  static const displayTick = Duration(milliseconds: 250);

  @override
  ConsumerState<DebugBleScreen> createState() => _DebugBleScreenState();
}

class _DebugBleScreenState extends ConsumerState<DebugBleScreen> {
  Timer? _tick;
  Timer? _scanStop;
  late final AppLifecycleListener _lifecycle;

  /// Kept in a field: `ref` is unusable in [dispose].
  late final BleHub _hub;

  @override
  void initState() {
    super.initState();
    _hub = ref.read(bleHubProvider);
    unawaited(_hub.start());
    _tick = Timer.periodic(DebugBleScreen.displayTick, (_) {
      if (mounted) setState(() {});
    });
    // Coming back from the system settings page may have granted access.
    _lifecycle = AppLifecycleListener(onResume: _hub.recheckPermission);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scanStop?.cancel();
    _hub.releaseScan(this);
    _lifecycle.dispose();
    super.dispose();
  }

  void _toggleScan() {
    setState(() {
      if (_hub.holdsScan(this)) {
        _scanStop?.cancel();
        _hub.releaseScan(this);
      } else {
        _hub.acquireScan(this);
        _scanStop = Timer(DebugBleScreen.manualScan, () {
          _hub.releaseScan(this);
          if (mounted) setState(() {});
        });
      }
    });
  }

  Future<void> _toggleTiming() async {
    final check = ref.read(timingCheckProvider);
    if (check.running) {
      check.stop();
    } else {
      await check.start();
    }
    if (mounted) setState(() {});
  }

  Future<void> _copyLog() async {
    final now = ref.read(clockProvider)();
    final text = StringBuffer();
    for (final side in FootSide.values) {
      final source = ref.read(insoleSourceProvider(side));
      text.writeln(_summary(source, now));
    }
    text
      ..writeln('---')
      ..write(ref.read(bleLogProvider).text());
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('คัดลอกบันทึกแล้ว')));
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(bleHubProvider);
    final now = ref.watch(clockProvider)();
    final left = ref.watch(insoleSourceProvider(FootSide.left));
    final right = ref.watch(insoleSourceProvider(FootSide.right));
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: const Text('BLE debug'),
      ),
      body: PageBody(
        children: [
          if (hub.readiness != BleReadiness.ready) _ReadinessCard(hub: hub),
          _ScanCard(
            hub: hub,
            now: now,
            manual: hub.holdsScan(this),
            onToggle: _toggleScan,
            onConnect: (id, name, side) =>
                ref.read(insoleSourceProvider(side)).connectTo(id, name: name),
          ),
          _FootCard(source: left, now: now),
          _FootCard(source: right, now: now),
          _TimingCard(
            check: ref.read(timingCheckProvider),
            manager: ref.read(deviceManagerProvider),
            mock: ref.read(mockInsolesProvider) != null,
            now: now,
            onToggle: _toggleTiming,
          ),
          _StorageCard(
            stats:
                ref.watch(temperatureStatsProvider).value ??
                TemperatureStats.empty,
            written: ref.read(temperatureRecorderProvider).written,
            failed: ref.read(temperatureRecorderProvider).failed,
          ),
          _LogCard(lines: ref.read(bleLogProvider).entries, onCopy: _copyLog),
        ],
      ),
    );
  }
}

// --- Thai messages (carried over to the Connection screen in S8B) ---------

String _sideTh(FootSide s) => s == FootSide.left ? 'ซ้าย' : 'ขวา';

String readinessMessageTh(BleReadiness r) => switch (r) {
  BleReadiness.checking => 'กำลังตรวจสอบบลูทูธ…',
  BleReadiness.needsPermission => 'ต้องอนุญาตให้แอปใช้บลูทูธก่อน',
  BleReadiness.permissionDenied =>
    'แอปไม่ได้รับอนุญาตให้ใช้บลูทูธ กรุณาเปิดสิทธิ์ในหน้าตั้งค่าของเครื่อง',
  BleReadiness.bluetoothOff => 'บลูทูธปิดอยู่ กรุณาเปิดบลูทูธ',
  BleReadiness.unavailable => 'เครื่องนี้ไม่มีบลูทูธ',
  BleReadiness.ready => 'บลูทูธพร้อมใช้งาน',
};

String problemMessageTh(LinkProblem p, FootSide slot) => switch (p.kind) {
  ProblemKind.wrongSide =>
    'แผ่นรองเท้านี้เป็นข้าง${_sideTh(p.reportedSide!)} '
        'ใช้เป็นข้าง${_sideTh(slot)}ไม่ได้',
  ProblemKind.mtuTooSmall =>
    'เชื่อมต่อได้ แต่รับข้อมูลไม่ได้ เพราะช่องส่งข้อมูลเล็กเกินไป '
        'กรุณาลองเชื่อมต่อใหม่',
  ProblemKind.calibrationInvalid =>
    'อ่านค่าปรับเทียบของแผ่นรองเท้าไม่ได้ จึงคำนวณแรงกดไม่ได้',
  ProblemKind.notAnInsole => 'อุปกรณ์นี้ไม่ใช่แผ่นรองเท้า SmartInsole',
  ProblemKind.inUseByOtherFoot => 'แผ่นรองเท้านี้เชื่อมต่อเป็นอีกข้างอยู่แล้ว',
};

/// Shown while streaming once no packet has arrived for this long. Display
/// only, worked out at read time (rule 2); S4 owns real staleness.
const _quietAfter = Duration(seconds: 2);

// --- English state text ---------------------------------------------------

String _stateLine(LinkState s, DateTime now) => switch (s) {
  LinkIdle() => 'IDLE',
  LinkBlocked(:final reason) => 'BLOCKED · ${reason.name}',
  LinkSearching() => 'SEARCHING',
  LinkConnecting(:final step) => 'CONNECTING · ${step.name}',
  LinkStreaming(:final mtu, :final samplesPerPacket, :final fsrCount) =>
    'STREAMING · MTU $mtu · $samplesPerPacket/pkt · N $fsrCount',
  LinkRetryWait(:final attempt, :final retryAt) =>
    'RETRY in ${_secs(retryAt.difference(now))} · attempt $attempt',
  LinkProblem(:final kind) => 'PROBLEM · ${kind.name}',
};

String _secs(Duration d) {
  final ms = d.inMilliseconds.clamp(0, 1 << 31);
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

String _ago(DateTime? t, DateTime now) =>
    t == null ? '—' : '${_secs(now.difference(t))} ago';

String _summary(BleDataSource s, DateTime now) {
  final st = s.stats;
  return [
    '${s.side.name.toUpperCase()}: ${_stateLine(s.state, now)}',
    '  device ${s.deviceId ?? '—'} · name "${st.advertisedName ?? ''}" · '
        'cal ${st.calibrationDeviceId ?? '—'}',
    '  packets ${st.packets} · ${st.packetRate(now).toStringAsFixed(2)}/s · '
        'last ${_ago(st.lastPacketAt, now)} · seq ${st.lastSeq ?? '—'}',
    '  seq gaps ${st.seqGaps} (${st.seqMissing} missing) · rejects '
        '${_rejects(st)} · before START ${st.droppedBeforeStart} · '
        'old conn ${st.droppedOldConnection} · t0 not forward '
        '${st.droppedNotForward}',
    '  admitted before START ack ${st.admittedBeforeAck} · missing at '
        'start ${st.missingAtStart}',
    '  sessions ${st.sessions} · link losses ${st.linkLosses} · failed '
        '${st.failedAttempts} · cal re-reads ${st.calibrationRereads}',
  ].join('\n');
}

String _rejects(LinkStats st) => st.rejects.isEmpty
    ? '0'
    : st.rejects.entries.map((e) => '${e.key.name} ${e.value}').join(', ');

// --- Cards ------------------------------------------------------------------

ButtonStyle get _compact =>
    OutlinedButton.styleFrom(minimumSize: const Size(0, Dimens.minTouchTarget));

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.hub});

  final BleHub hub;

  @override
  Widget build(BuildContext context) {
    final r = hub.readiness;
    final (String, VoidCallback)? action = switch (r) {
      BleReadiness.needsPermission => ('Allow', hub.requestPermission),
      BleReadiness.permissionDenied => ('Open settings', hub.openSettings),
      BleReadiness.bluetoothOff => ('Turn on Bluetooth', hub.turnOnBluetooth),
      _ => null,
    };
    return Card(
      key: const ValueKey('ble-readiness'),
      color: StatusColors.careful.background,
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              readinessMessageTh(r),
              style: AppText.bodyStrong.copyWith(
                color: StatusColors.careful.text,
              ),
            ),
            Text('readiness: ${r.name}', style: AppText.secondary),
            if (action != null) ...[
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('ble-readiness-action'),
                onPressed: action.$2,
                child: Text(action.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({
    required this.hub,
    required this.now,
    required this.manual,
    required this.onToggle,
    required this.onConnect,
  });

  final BleHub hub;
  final DateTime now;
  final bool manual;
  final VoidCallback onToggle;
  final void Function(String id, String? name, FootSide side) onConnect;

  @override
  Widget build(BuildContext context) {
    final seen = hub.seen;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Insoles nearby', style: AppText.cardTitle),
                ),
                OutlinedButton(
                  key: const ValueKey('scan-button'),
                  style: _compact,
                  onPressed: hub.readiness == BleReadiness.ready
                      ? onToggle
                      : null,
                  child: Text(manual ? 'Stop scan' : 'Scan'),
                ),
              ],
            ),
            Text(
              'scan ${hub.scanning ? 'running' : 'off'} · by service UUID · '
              'names may be cached by the OS; the side comes from foot_side',
              style: AppText.secondary.copyWith(color: AppColors.inkMuted),
            ),
            if (seen.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No insole seen yet', style: AppText.secondary),
              ),
            for (final s in seen) ...[
              const Divider(height: 24),
              Text(s.deviceId, style: AppText.bodyStrong),
              Text(
                'name "${s.sighting.name ?? ''}" (may be cached) · rssi '
                '${s.sighting.rssi} · seen ${_ago(s.at, now)}'
                '${switch (hub.claimedBy(s.deviceId)) {
                  null => '',
                  final side => ' · bound to ${side.name.toUpperCase()}',
                }}',
                style: AppText.secondary.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final side in FootSide.values)
                    OutlinedButton(
                      key: ValueKey('connect-${s.deviceId}-${side.name}'),
                      style: _compact,
                      onPressed: () =>
                          onConnect(s.deviceId, s.sighting.name, side),
                      child: Text('Connect as ${side.name.toUpperCase()}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FootCard extends StatelessWidget {
  const _FootCard({required this.source, required this.now});

  final BleDataSource source;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final state = source.state;
    final st = source.stats;
    final side = source.side;
    final status = st.lastStatus;
    final temp = st.lastTemp;
    // Quiet = streaming, yet nothing since START or since the last packet.
    final quietFrom = switch (state) {
      LinkStreaming(:final since) =>
        st.lastPacketAt != null && st.lastPacketAt!.isAfter(since)
            ? st.lastPacketAt!
            : since,
      _ => null,
    };
    final quietFor = quietFrom == null ? null : now.difference(quietFrom);
    final quiet = quietFor != null && quietFor > _quietAfter;
    final dot = state is LinkStreaming && !quiet
        ? AppColors.connected
        : AppColors.inkSubtle;
    final canConnect =
        source.deviceId != null && (state is LinkIdle || state is LinkProblem);
    final canDisconnect = state is! LinkIdle && state is! LinkProblem;

    return Card(
      key: ValueKey('foot-card-${side.name}'),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${side.name.toUpperCase()} foot',
                  style: AppText.cardTitle,
                ),
              ],
            ),
            Text(
              _stateLine(state, now),
              key: ValueKey('foot-state-${side.name}'),
              style: AppText.bodyStrong,
            ),
            if (state is LinkProblem)
              _Banner(
                palette: StatusColors.rest,
                th: problemMessageTh(state, side),
                en: state.detail,
              ),
            if (state is LinkBlocked)
              _Banner(
                palette: StatusColors.careful,
                th: readinessMessageTh(state.reason),
                en: 'waiting for ${state.reason.name}',
              ),
            if (state is LinkRetryWait)
              _Banner(
                palette: StatusColors.careful,
                th: 'กำลังเชื่อมต่อใหม่',
                en: state.lastError,
              ),
            if (quiet)
              _Banner(
                palette: StatusColors.noData,
                th: 'ไม่ได้รับข้อมูลมา ${quietFor.inSeconds} วินาที',
                en:
                    'streaming, but no packet for over '
                    '${_quietAfter.inSeconds} s',
              ),
            const SizedBox(height: 8),
            _kv('device', source.deviceId ?? '—'),
            _kv('name', '"${st.advertisedName ?? ''}" (display only)'),
            _kv('calibration', st.calibrationDeviceId ?? '—'),
            _kv(
              'status',
              status == null
                  ? '—'
                  : 'side ${status.footSide.name} · fw ${status.fwMajor}.'
                        '${status.fwMinor} · ${status.batteryPct} % '
                        '(${status.batteryMv} mV) · ${status.state.name} · '
                        'error ${status.errorCode}',
            ),
            _kv(
              'packets',
              '${st.packets} · ${st.packetRate(now).toStringAsFixed(2)}/s '
                  '(${LinkStats.rateWindow.inSeconds} s) · last '
                  '${_ago(st.lastPacketAt, now)}',
            ),
            _kv(
              'seq',
              '${st.lastSeq ?? '—'} · gaps ${st.seqGaps} '
                  '(${st.seqMissing} missing)',
            ),
            _kv('rejects', _rejects(st)),
            _kv(
              'dropped',
              'before START ${st.droppedBeforeStart} · old conn '
                  '${st.droppedOldConnection} · t0 not forward '
                  '${st.droppedNotForward}',
            ),
            _kv(
              'start',
              'admitted before ack ${st.admittedBeforeAck} · missing at '
                  'start ${st.missingAtStart}',
            ),
            _kv(
              'sessions',
              '${st.sessions} · link losses ${st.linkLosses} · failed '
                  '${st.failedAttempts} · cal re-reads ${st.calibrationRereads}',
            ),
            _kv(
              'kPa',
              st.lastKpa == null
                  ? '—'
                  : st.lastKpa!.map((v) => v.toStringAsFixed(1)).join(' · '),
            ),
            _kv(
              'temp',
              temp == null
                  ? '—'
                  : 'forefoot ${temp.forefootC?.toStringAsFixed(2) ?? 'n/a'} °C'
                        ' · heel ${temp.heelC?.toStringAsFixed(2) ?? 'n/a'} °C'
                        ' · ${temp.quality.name}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: ValueKey('reconnect-${side.name}'),
                  style: _compact,
                  onPressed: canConnect ? source.connect : null,
                  child: Text(state is LinkProblem ? 'Retry' : 'Connect'),
                ),
                OutlinedButton(
                  key: ValueKey('disconnect-${side.name}'),
                  style: _compact,
                  onPressed: canDisconnect ? source.disconnect : null,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$k  ',
            style: AppText.secondary.copyWith(color: AppColors.inkMuted),
          ),
          TextSpan(text: v, style: AppText.secondary),
        ],
      ),
    ),
  );
}

/// S4 checkpoint: starts the timing log (SYNC_TIME every 10 s, a file in
/// the app's private storage) and shows each foot's clock figures.
/// S6A phone check: temperature rows in the database survive a restart.
class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.stats,
    required this.written,
    required this.failed,
  });

  final TemperatureStats stats;
  final int written;
  final int failed;

  @override
  Widget build(BuildContext context) {
    String time(int? ms) {
      if (ms == null) return '—';
      final t = DateTime.fromMillisecondsSinceEpoch(ms);
      String two(int v) => v.toString().padLeft(2, '0');
      return '${t.month}/${t.day} '
          '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    }

    return Card(
      key: const ValueKey('storage-card'),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Storage', style: AppText.cardTitle),
            for (final side in FootSide.values)
              Text(
                '${side.name.toUpperCase()}  temperature rows '
                '${stats.count[side] ?? 0} · latest '
                '${time(stats.latestMs[side])}',
                key: ValueKey('storage-${side.name}'),
                style: AppText.secondary,
              ),
            Text(
              'this run: written $written · failed $failed',
              style: AppText.secondary.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimingCard extends StatelessWidget {
  const _TimingCard({
    required this.check,
    required this.manager,
    required this.mock,
    required this.now,
    required this.onToggle,
  });

  final TimingCheck check;
  final DeviceManager manager;
  final bool mock;
  final DateTime now;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final started = check.startedAt;
    return Card(
      key: const ValueKey('timing-card'),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Timing check', style: AppText.cardTitle),
                ),
                OutlinedButton(
                  key: const ValueKey('timing-toggle'),
                  style: _compact,
                  onPressed: mock ? null : onToggle,
                  child: Text(check.running ? 'Stop' : 'Start'),
                ),
              ],
            ),
            Text(
              mock
                  ? 'BLE only: the mock data source is active'
                  : check.running && started != null
                  ? 'running ${_secs(now.difference(started))} · '
                        '${check.lines} lines · SYNC_TIME every 10 s'
                  : 'off · SYNC_TIME every 5 min',
              style: AppText.secondary.copyWith(color: AppColors.inkMuted),
            ),
            if (check.path != null)
              Text('file ${check.path}', style: AppText.secondary),
            for (final side in FootSide.values) _foot(side),
          ],
        ),
      ),
    );
  }

  Widget _foot(FootSide side) {
    final t = manager.timing(side, takeSteps: false);
    String ms(double? v) => v == null ? '—' : v.toStringAsFixed(2);
    final settling = t.offsetMs == null || t.targetMs == null
        ? null
        : t.offsetMs! - t.targetMs!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '${side.name.toUpperCase()}  session ${t.session ?? '—'} · '
        'pkts ${t.packets} · lost ${t.lost} · settling ${ms(settling)} ms · '
        'last excess ${ms(t.lastExcessMs)} ms · step ${ms(t.stepMinMs)}–'
        '${ms(t.stepMaxMs)} ms · clamps ${t.clamps}',
        style: AppText.secondary,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.palette, required this.th, required this.en});

  final StatusPalette palette;
  final String th;
  final String en;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(th, style: AppText.bodyStrong.copyWith(color: palette.text)),
          Text(en, style: AppText.secondary.copyWith(color: palette.text)),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.lines, required this.onCopy});

  final List<Object> lines;
  final VoidCallback onCopy;

  /// Lines shown on screen; "Copy log" copies all of them.
  static const shown = 40;

  @override
  Widget build(BuildContext context) {
    final recent = lines.reversed.take(shown).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Event log (${lines.length})',
                    style: AppText.cardTitle,
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('copy-log'),
                  style: _compact,
                  onPressed: onCopy,
                  child: const Text('Copy log'),
                ),
              ],
            ),
            Text(
              'newest first',
              style: AppText.secondary.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 4),
            for (final l in recent) Text('$l', style: AppText.secondary),
          ],
        ),
      ),
    );
  }
}
