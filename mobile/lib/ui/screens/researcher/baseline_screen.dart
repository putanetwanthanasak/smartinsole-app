import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../config/thresholds.dart';
import '../../../device/device_providers.dart';
import '../../../gait/baseline_recorder.dart';
import '../../../gait/gait_providers.dart';
import '../../../gait/preprocess.dart';
import '../../../storage/baseline_repository.dart';
import '../../../storage/storage_providers.dart';
import '../../clock.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/back_link.dart';
import '../../widgets/buttons.dart';
import '../../widgets/info_box.dart';
import '../../widgets/page_title.dart';
import '../connection/connection_widgets.dart' show ConnectDimens;

/// "ซ้าย" / "ขวา".
String _sideTh(FootSide s) => s == FootSide.left ? 'ซ้าย' : 'ขวา';

/// One foot's line on the Researcher card and this screen: the connected
/// insole and whether it has a quiet-standing baseline (S9).
class BaselineFootStatus {
  const BaselineFootStatus(this.side, this.insoleId, this.stored);

  final FootSide side;

  /// The connected insole's calibration `device_id`; null when none is.
  final String? insoleId;
  final FootBaseline? stored;
}

List<BaselineFootStatus> baselineStatus(
  List<FootBaseline> stored,
  String? Function(FootSide) insoleId,
) => [
  for (final side in FootSide.values)
    BaselineFootStatus(side, insoleId(side), () {
      final id = insoleId(side);
      for (final b in stored) {
        if (b.side == side && b.insoleId == id) return b;
      }
      return null;
    }()),
];

/// The Researcher row's value: "บันทึกแล้วทั้งสองข้าง · 1 พ.ย. 10:32",
/// "ยังไม่ได้บันทึก: ขวา", or "เชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน".
String baselineStatusLine(List<BaselineFootStatus> feet) {
  if (feet.any((f) => f.insoleId == null)) {
    return 'เชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน';
  }
  final missing = [
    for (final f in feet)
      if (f.stored == null) _sideTh(f.side),
  ];
  if (missing.isNotEmpty) return 'ยังไม่ได้บันทึก: ${missing.join(', ')}';
  final at = feet
      .map((f) => f.stored!.recordedAtMs)
      .reduce((a, b) => a < b ? a : b);
  return 'บันทึกแล้วทั้งสองข้าง · '
      '${thaiDateTimeBE(DateTime.fromMillisecondsSinceEpoch(at))}';
}

/// What a failure says (Thai, then English for the researcher).
String baselineFailureText(BaselineFailure f, FootSide? side) {
  final foot = side == null ? '' : ' (เท้า${_sideTh(side)})';
  final why = switch (f) {
    BaselineFailure.lostPackets => 'ข้อมูลขาดหาย$foot · Packets were lost.',
    BaselineFailure.reconnected =>
      'แผ่นรองเท้าเชื่อมต่อใหม่$foot · The insole reconnected.',
    BaselineFailure.calibrating =>
      'กำลังตั้งค่าศูนย์ (TARE)$foot · A TARE was running.',
    BaselineFailure.moved =>
      'ผู้เข้าร่วมขยับหรือเดิน$foot · Movement detected.',
    BaselineFailure.notLoaded =>
      'ไม่ได้ลงน้ำหนักบนแผ่นรองเท้า$foot · The foot was not loaded.',
    BaselineFailure.wrongInsole =>
      'แผ่นรองเท้าไม่ใช่รุ่น 8 เซนเซอร์$foot · Not an 8-sensor insole.',
    BaselineFailure.stopped =>
      'แผ่นรองเท้าหยุดส่งข้อมูล$foot · An insole stopped streaming.',
  };
  return '$why ไม่ได้บันทึก ให้บันทึกใหม่ · Not saved; record again.';
}

/// Researcher › "บันทึกค่ายืนนิ่ง 30 วินาที" (S9, Model A preprocessing
/// "ทางเอ"): records both insoles' quiet-standing baseline from the 50 Hz
/// path and stores it per insole. Researcher-only; Thai with English
/// secondary text, like the capture screens.
class BaselineScreen extends ConsumerStatefulWidget {
  const BaselineScreen({super.key});

  @override
  ConsumerState<BaselineScreen> createState() => _BaselineScreenState();
}

enum _Phase { idle, recording, saving, failed, saved }

class _BaselineScreenState extends ConsumerState<BaselineScreen> {
  _Phase _phase = _Phase.idle;
  BaselineRecorder? _recorder;
  StreamSubscription<Object?>? _sub;

  String? _insoleId(FootSide side) =>
      ref.read(insoleDataSourceProvider(side)).calibration?.deviceId;

  void _start() {
    final ids = {for (final s in FootSide.values) s: _insoleId(s)};
    if (ids.values.any((id) => id == null)) return;
    final recorder = BaselineRecorder(
      spec: ref.read(preprocessSpecProvider),
      thresholds: ref.read(thresholdsProvider),
      insoleIds: {for (final e in ids.entries) e.key: e.value!},
    );
    _sub?.cancel();
    _sub = ref.read(deviceManagerProvider).batches.listen(recorder.add);
    setState(() {
      _recorder = recorder;
      _phase = _Phase.recording;
    });
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// At 10 Hz while recording: a foot that stopped streaming fails it
  /// (read at read time, rule 2); a finished recording is saved once.
  Future<void> _tick(bool bothStreaming) async {
    final r = _recorder;
    if (_phase != _Phase.recording || r == null) return;
    if (!bothStreaming) r.fail(BaselineFailure.stopped);
    if (r.failure != null) {
      _stop();
      setState(() => _phase = _Phase.failed);
      return;
    }
    if (r.done) {
      _stop();
      // Ticks during the save return at the phase check: saved once.
      _phase = _Phase.saving;
      final now = ref.read(clockProvider)().millisecondsSinceEpoch;
      final repo = ref.read(baselineRepositoryProvider);
      for (final b in r.result(now)!) {
        await repo.save(b);
      }
      if (mounted) setState(() => _phase = _Phase.saved);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(displaySnapshotProvider, (_, next) {
      final s = next.value;
      _tick(s != null && s.left.usable && s.right.usable);
    });
    final snap = ref.watch(displaySnapshotProvider).value;
    final streaming = snap != null && snap.left.usable && snap.right.usable;
    final stored = ref.watch(storedBaselinesProvider).value ?? const [];
    final feet = baselineStatus(stored, _insoleId);
    final seconds = ref.watch(preprocessSpecProvider).baselineSeconds;
    final canStart =
        streaming &&
        feet.every((f) => f.insoleId != null) &&
        _phase != _Phase.recording &&
        _phase != _Phase.saving;
    final r = _recorder;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('baseline-scroll'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pageTopPushed,
            Dimens.pagePadding,
            Dimens.pageBottomPushed,
          ),
          children: [
            const BackLink(),
            const SizedBox(height: Dimens.tightGap),
            PageTitle(
              'บันทึกค่ายืนนิ่ง $seconds วินาที',
              subtitle: 'Quiet-standing baseline for Model A',
            ),
            const SizedBox(height: Dimens.sectionGap),
            InfoBox(
              text:
                  'ให้ผู้เข้าร่วมใส่แผ่นรองเท้าทั้งสองข้าง ยืนนิ่ง ลงน้ำหนัก'
                  'สองเท้าเท่ากัน ตลอด $seconds วินาที · Stand still on both '
                  'insoles, weight on both feet, for $seconds s.',
            ),
            const SizedBox(height: Dimens.sectionGap),
            for (final f in feet) ...[
              _FootLine(
                status: f,
                progress: _phase == _Phase.recording && r != null
                    ? r.progress(f.side)
                    : null,
              ),
              const SizedBox(height: Dimens.cardGap),
            ],
            if (!streaming && _phase != _Phase.saved)
              const Padding(
                padding: EdgeInsets.only(bottom: Dimens.cardGap),
                child: WarningBox(
                  text:
                      'เชื่อมต่อแผ่นรองเท้าทั้งสองข้างให้ส่งข้อมูลก่อน · '
                      'Both insoles must be streaming.',
                ),
              ),
            if (_phase == _Phase.failed && r?.failure != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Dimens.cardGap),
                child: WarningBox(
                  key: const ValueKey('baseline-failed'),
                  text: baselineFailureText(r!.failure!, r.failedSide),
                ),
              ),
            if (_phase == _Phase.saved)
              const Padding(
                padding: EdgeInsets.only(bottom: Dimens.cardGap),
                child: InfoBox(
                  key: ValueKey('baseline-saved'),
                  icon: LucideIcons.circle_check,
                  text:
                      'บันทึกแล้ว Model A จะใช้ค่านี้กับแผ่นรองเท้าคู่นี้ · '
                      'Saved for this pair of insoles.',
                ),
              ),
            if (_phase == _Phase.recording)
              SecondaryButton(
                key: const ValueKey('baseline-cancel'),
                label: 'ยกเลิก',
                onPressed: () {
                  _stop();
                  setState(() => _phase = _Phase.idle);
                },
              )
            else
              PrimaryButton(
                key: const ValueKey('baseline-start'),
                label: _phase == _Phase.idle ? 'เริ่มบันทึก' : 'บันทึกใหม่',
                icon: LucideIcons.timer,
                onPressed: canStart ? _start : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _FootLine extends StatelessWidget {
  const _FootLine({required this.status, this.progress});

  final BaselineFootStatus status;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final s = status.stored;
    final p = progress;
    return DecoratedBox(
      key: ValueKey('baseline-foot-${status.side.name}'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.smallCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'เท้า${_sideTh(status.side)} · ${status.insoleId ?? 'ไม่ได้เชื่อมต่อ'}',
              style: AppText.bodyStrong,
            ),
            const SizedBox(height: Dimens.textGap),
            Text(
              s == null
                  ? 'ยังไม่ได้บันทึก · No baseline'
                  : 'บันทึกแล้ว ${thaiDateTimeBE(DateTime.fromMillisecondsSinceEpoch(s.recordedAtMs))}'
                        ' · ${s.sampleCount} samples',
              style: AppText.secondary,
            ),
            if (p != null) ...[
              const SizedBox(height: Dimens.tightGap),
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  ConnectDimens.progressRadius,
                ),
                child: LinearProgressIndicator(
                  key: ValueKey('baseline-progress-${status.side.name}'),
                  value: p,
                  minHeight: ConnectDimens.progressHeight,
                  color: AppColors.primary,
                  backgroundColor: AppColors.track,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
