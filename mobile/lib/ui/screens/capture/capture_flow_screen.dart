import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../capture/capture_protocol.dart';
import '../../../capture/capture_providers.dart';
import '../../../capture/capture_session.dart';
import '../../../device/device_providers.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/placeholder_body.dart';
import 'capture_summary.dart';
import 'capture_widgets.dart';

/// One capture session from calibration to the summary. While practising
/// or recording the phone is in a pocket: nothing here reacts to a short
/// touch, Back is blocked, the screen stays on, and every event is a
/// sound + vibration cue. Owns [session] and disposes it.
class CaptureFlowScreen extends ConsumerStatefulWidget {
  const CaptureFlowScreen({super.key, required this.session});

  final CaptureSession session;

  @override
  ConsumerState<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends ConsumerState<CaptureFlowScreen> {
  late final _wakelock = ref.read(wakelockProvider);
  Timer? _restTick;

  CaptureSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _wakelock(true).catchError((Object _) {});
    s.addListener(_onSession);
    _onSession();
  }

  void _onSession() {
    // The rest clock only needs a once-a-second redraw; its value is read
    // from the session at build time.
    if (s.phase == CapturePhase.saved) {
      _restTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _restTick?.cancel();
      _restTick = null;
    }
  }

  @override
  void dispose() {
    _wakelock(false).catchError((Object _) {});
    _restTick?.cancel();
    s
      ..removeListener(_onSession)
      ..dispose();
    super.dispose();
  }

  bool get _busy => switch (s.phase) {
    CapturePhase.practice ||
    CapturePhase.recording ||
    CapturePhase.saving => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: _busy ? null : const AppBackButton(),
            titleSpacing: _busy ? null : 0,
            title: Text(s.subject.code.code),
            actions: [
              if (!_busy && s.phase != CapturePhase.done)
                IconButton(
                  key: const ValueKey('capture-summary-button'),
                  tooltip: 'สรุป · Summary',
                  icon: const Icon(LucideIcons.list_checks),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CaptureSummaryScreen(session: s),
                    ),
                  ),
                ),
            ],
          ),
          body: switch (s.phase) {
            CapturePhase.ready => _Ready(session: s),
            CapturePhase.practice => _Practice(session: s),
            CapturePhase.recording => _Recording(session: s),
            CapturePhase.saving => const _Saving(),
            CapturePhase.saved => _Saved(session: s),
            CapturePhase.done => PageBody(
              children: [CaptureSummary(session: s)],
            ),
          },
        ),
      ),
    );
  }
}

/// What the trial is: gait name (Thai + English) and the instruction.
class _TrialHeader extends StatelessWidget {
  const _TrialHeader({required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context) {
    final plan = session.current.plan;
    final g = plan.gait;
    // Ready and practice: the attempt about to be recorded.
    final attempt =
        session.phase == CapturePhase.ready ||
            session.phase == CapturePhase.practice
        ? session.current.attempts.length + 1
        : session.attempt?.attempt ?? session.current.attempts.length;
    final title = g == null
        ? 'Calibration'
        : 'Trial ${plan.number} of ${session.order.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title · attempt $attempt', style: AppText.secondary),
        Text(g?.th ?? 'ยืนนิ่ง', style: AppText.screenTitle),
        Text(g?.en ?? 'Standing still', style: AppText.cardTitle),
        const SizedBox(height: 6),
        Text(
          g?.instructionTh ?? 'ยืนนิ่ง ลงน้ำหนักสองเท้าเท่ากัน',
          style: AppText.body,
        ),
        Text(
          g?.instructionEn ?? 'Stand still, weight on both feet',
          style: AppText.secondary,
        ),
        if (g == GaitClass.antalgic) ...[
          const SizedBox(height: 8),
          CaptureBanner(
            palette: StatusColors.careful,
            icon: LucideIcons.footprints,
            text:
                'ข้างที่เจ็บ: '
                '${session.subject.code.painSide == FootSide.left ? 'ซ้าย' : 'ขวา'}'
                ' · Pain side: ${sideName(session.subject.code.painSide).toUpperCase()}',
          ),
        ],
        if (g == GaitClass.rotatedFoot && session.phase != CapturePhase.ready)
          if (session.attempt?.rotation ?? session.rotation case final r?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CaptureBanner(
                palette: StatusColors.careful,
                icon: LucideIcons.footprints,
                text: '${r.th} · ${r.en}',
              ),
            ),
      ],
    );
  }
}

class _Ready extends ConsumerWidget {
  const _Ready({required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(displaySnapshotProvider).value;
    final bothUsable = snap != null && snap.left.usable && snap.right.usable;
    final s = session;
    final calibration = s.current.plan.isCalibration;
    final canGo = s.canStart && bothUsable;
    return PageBody(
      children: [
        _TrialHeader(session: s),
        if (s.current.plan.gait == GaitClass.rotatedFoot)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Direction (required)', style: AppText.bodyStrong),
              const SizedBox(height: 6),
              SegmentedButton<Rotation>(
                key: const ValueKey('capture-rotation'),
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  for (final r in Rotation.values)
                    ButtonSegment(value: r, label: Text('${r.th}\n${r.en}')),
                ],
                selected: {?s.rotation},
                onSelectionChanged: (v) {
                  if (v.isNotEmpty) s.setRotation(v.first);
                },
              ),
            ],
          ),
        if (snap != null)
          Column(
            children: [
              for (final side in FootSide.values) ...[
                FootLinkRow(view: snap.of(side)),
                const SizedBox(height: 8),
              ],
            ],
          ),
        // Before the first display tick there is nothing to judge yet.
        if (snap != null && !bothUsable)
          Text(
            'Both feet must be streaming to start.',
            style: AppText.small.copyWith(fontWeight: FontWeight.w600),
          ),
        if (calibration)
          FilledButton(
            key: const ValueKey('capture-record'),
            onPressed: canGo ? s.startRecording : null,
            child: Text(
              'Start recording (${s.timings.calibration.inSeconds} s)',
            ),
          )
        else ...[
          FilledButton(
            key: const ValueKey('capture-practice'),
            onPressed: canGo ? s.startPractice : null,
            child: Text(
              'Start practice (${s.timings.practice.inSeconds} s), '
              'then record',
            ),
          ),
          OutlinedButton(
            key: const ValueKey('capture-record'),
            onPressed: canGo ? s.startRecording : null,
            child: const Text('Record now, no practice'),
          ),
        ],
        Text(
          'Recording lasts ${mmss(s.plannedDuration)} and stops on its own. '
          'Cues: start · 10 s left · end · link lost.',
          style: AppText.small,
        ),
      ],
    );
  }
}

class _Timer extends StatelessWidget {
  const _Timer({required this.remaining, required this.caption});

  final Duration remaining;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            mmss(remaining),
            key: const ValueKey('capture-timer'),
            style: AppText.captureTimer,
          ),
        ),
        Text(caption, style: AppText.secondary, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Practice and recording: the content scrolls, the hold buttons stay
/// pinned at the bottom so they are always on screen.
class _PocketLayout extends StatelessWidget {
  const _PocketLayout({required this.content, required this.buttons});

  final List<Widget> content;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: PageBody(children: content)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.pagePadding,
              0,
              Dimens.pagePadding,
              Dimens.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  buttons[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Practice extends StatelessWidget {
  const _Practice({required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context) {
    return _PocketLayout(
      content: [
        const CaptureBanner(
          palette: StatusColors.noData,
          icon: LucideIcons.footprints,
          text: 'ฝึกเดิน · Practice — not recorded',
        ),
        _Timer(
          remaining: session.remaining ?? Duration.zero,
          caption: 'Recording starts on its own',
        ),
        _TrialHeader(session: session),
      ],
      buttons: [
        HoldButton(
          key: const ValueKey('capture-cancel-practice'),
          label: 'Cancel practice',
          icon: LucideIcons.x,
          onHeld: session.cancelPractice,
        ),
      ],
    );
  }
}

class _Recording extends StatelessWidget {
  const _Recording({required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return _PocketLayout(
      content: [
        const CaptureBanner(
          palette: StatusColors.rest,
          icon: LucideIcons.circle_dot,
          text: 'กำลังบันทึก · Recording',
        ),
        for (final side in s.linkLost)
          CaptureBanner(
            key: ValueKey('capture-link-lost-${side.name}'),
            palette: StatusColors.rest,
            icon: LucideIcons.bluetooth_off,
            text:
                '${sideName(side)[0].toUpperCase()}${sideName(side).substring(1)}'
                ' foot link lost — the gap is recorded',
          ),
        if (s.markedInvalid)
          const CaptureBanner(
            key: ValueKey('capture-marked'),
            palette: StatusColors.careful,
            icon: LucideIcons.flag,
            text: 'Marked invalid — hold again when back in form',
          ),
        _Timer(
          remaining: s.remaining ?? Duration.zero,
          caption: 'Stops on its own',
        ),
        _TrialHeader(session: s),
      ],
      buttons: [
        HoldButton(
          key: const ValueKey('capture-mark'),
          label: s.markedInvalid ? 'Valid again' : 'Mark invalid',
          icon: LucideIcons.flag,
          palette: StatusColors.careful,
          onHeld: s.toggleMarkInvalid,
        ),
        HoldButton(
          key: const ValueKey('capture-stop'),
          label: 'Stop early',
          icon: LucideIcons.square,
          palette: StatusColors.rest,
          onHeld: s.stopEarly,
        ),
      ],
    );
  }
}

class _Saving extends StatelessWidget {
  const _Saving();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Saving…', style: AppText.cardTitle));
  }
}

class _Saved extends StatelessWidget {
  const _Saved({required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final a = s.attempt!;
    final gaps = s.lastGaps;
    final nextIndex = s.trials.indexWhere((t) => !t.done);
    final next = nextIndex < 0 ? null : s.trials[nextIndex].plan;
    return PageBody(
      children: [
        CaptureBanner(
          palette: a.valid && gaps.isEmpty
              ? StatusColors.safe
              : StatusColors.careful,
          icon: LucideIcons.save,
          text:
              'Saved ${a.baseName} · ${endReasonId(a.endReason!)}'
              '${a.valid ? '' : ' · invalid (${a.invalidReason})'}',
        ),
        _TrialHeader(session: s),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Dimens.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final side in FootSide.values)
                  Text(
                    '${sideName(side)}: ${a.samples[side] ?? 0} samples',
                    style: AppText.secondary,
                  ),
                Text(
                  gaps.isEmpty
                      ? 'No gaps'
                      : '${gaps.length} gap(s): '
                            '${[for (final g in gaps) '${sideName(g.side)} ${g.kind}'].join(', ')}'
                            ' — consider Redo',
                  key: const ValueKey('capture-gaps'),
                  style: AppText.bodyStrong,
                ),
              ],
            ),
          ),
        ),
        Text(
          'พัก · Rest ${mmss(s.restElapsed ?? Duration.zero)} — as long as '
          'the volunteer needs',
          key: const ValueKey('capture-rest'),
          style: AppText.body,
        ),
        FilledButton(
          key: const ValueKey('capture-next'),
          onPressed: s.next,
          child: Text(
            next == null ? 'Finish' : 'Next: ${next.gait?.en ?? 'Calibration'}',
          ),
        ),
        OutlinedButton(
          key: const ValueKey('capture-redo'),
          onPressed: () => _confirmRedo(context),
          child: const Text('Redo this trial'),
        ),
      ],
    );
  }

  Future<void> _confirmRedo(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redo this trial?'),
        content: const Text(
          'This attempt is kept on the phone, marked invalid (redo), and '
          'the trial is recorded again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('capture-redo-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redo'),
          ),
        ],
      ),
    );
    if (ok ?? false) session.redo();
  }
}
