import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../device/insole_commands.dart';
import '../../motion.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/confirm_sheet.dart';
import 'researcher_providers.dart';

String _foot(FootSide s) => s == FootSide.left ? 'เท้าซ้าย' : 'เท้าขวา';

String _feet(Iterable<FootSide> sides) => sides.map(_foot).join(' และ ');

enum _TarePhase { confirm, running, done, failed, refused }

/// "ตั้งค่าศูนย์เซนเซอร์" (DESIGN-SPEC §10.2, board SettingsDTare). The
/// in-progress, done and failed states are not on the boards (§14): they
/// reuse the same sheet with draft copy.
class TareSheet extends ConsumerStatefulWidget {
  const TareSheet({super.key});

  @override
  ConsumerState<TareSheet> createState() => _TareSheetState();
}

class _TareSheetState extends ConsumerState<TareSheet> {
  _TarePhase _phase = _TarePhase.confirm;
  Map<FootSide, TareOutcome> _outcomes = const {};

  Future<void> _run() async {
    setState(() => _phase = _TarePhase.running);
    try {
      final r = await ref.read(insoleCommandsProvider).tare();
      if (!mounted) return;
      setState(() {
        _outcomes = r;
        _phase = r.values.every((o) => o == TareOutcome.done)
            ? _TarePhase.done
            : _TarePhase.failed;
      });
    } on CommandRefused {
      if (mounted) setState(() => _phase = _TarePhase.refused);
    } on Object {
      if (mounted) setState(() => _phase = _TarePhase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _TarePhase.confirm => ConfirmSheet(
        key: const ValueKey('tare-sheet'),
        title: 'ตั้งค่าศูนย์เซนเซอร์',
        text: 'ใช้เมื่อค่าแรงกดไม่เป็นศูนย์ ทั้งที่ไม่มีใครเหยียบแผ่นรองเท้า',
        steps: const [
          'ให้ผู้สวมนั่งลง แล้วยกเท้าทั้งสองข้างให้ลอยจากพื้น',
          'กด "ตั้งค่าศูนย์" แล้วรอจนขึ้นว่าเสร็จ',
        ],
        warning: 'อย่าทำระหว่างเก็บข้อมูลวิจัย ค่าแรงกดที่บันทึกจะเพี้ยน',
        cancelLabel: 'ยกเลิก',
        confirmLabel: 'ตั้งค่าศูนย์',
        onConfirm: _run,
      ),
      _TarePhase.running => ConfirmSheet(
        key: const ValueKey('tare-running'),
        title: 'กำลังตั้งค่าศูนย์…',
        text: 'ยกเท้าให้ลอยไว้จนกว่าจะขึ้นว่าเสร็จ',
        // No buttons: a sent TARE can't be taken back; the sheet moves on
        // to done or failed by itself.
        cancelLabel: null,
        child: Motion.reduced(context)
            ? null
            : const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
      ),
      _TarePhase.done => ConfirmSheet(
        key: const ValueKey('tare-done'),
        title: 'ตั้งค่าศูนย์เสร็จแล้ว',
        text: '${_feet(_outcomes.keys)} ตั้งค่าศูนย์เรียบร้อย',
        cancelLabel: 'ปิด',
      ),
      _TarePhase.failed => ConfirmSheet(
        key: const ValueKey('tare-failed'),
        title: 'ตั้งค่าศูนย์ไม่สำเร็จ',
        text: _outcomes.isEmpty
            ? 'ส่งคำสั่งไม่สำเร็จ ลองเชื่อมต่อใหม่แล้วทำอีกครั้ง'
            : 'ไม่ได้รับการตอบกลับจาก${_feet([for (final e in _outcomes.entries)
                if (e.value != TareOutcome.done) e.key])} ลองเชื่อมต่อใหม่แล้วทำอีกครั้ง',
        cancelLabel: 'ปิด',
      ),
      _TarePhase.refused => const _RefusedSheet(),
    };
  }
}

/// "รีสตาร์ตแผ่นรองเท้า" confirmation (§14: the TARE sheet pattern).
/// Draft copy.
class RebootSheet extends ConsumerStatefulWidget {
  const RebootSheet({super.key});

  @override
  ConsumerState<RebootSheet> createState() => _RebootSheetState();
}

class _RebootSheetState extends ConsumerState<RebootSheet> {
  bool _refused = false;

  @override
  Widget build(BuildContext context) {
    if (_refused) return const _RefusedSheet();
    return ConfirmSheet(
      key: const ValueKey('reboot-sheet'),
      title: 'รีสตาร์ตแผ่นรองเท้า',
      text:
          'แผ่นรองเท้าที่เชื่อมต่ออยู่จะปิดแล้วเปิดใหม่ '
          'แอปจะเชื่อมต่อกลับเองภายในไม่กี่วินาที',
      warning: 'อย่าทำระหว่างเก็บข้อมูลวิจัย การเชื่อมต่อจะหลุดระหว่างบันทึก',
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'รีสตาร์ต',
      onConfirm: () async {
        try {
          await ref.read(insoleCommandsProvider).reboot();
        } on CommandRefused {
          if (mounted) setState(() => _refused = true);
          return;
        } on Object {
          // The link may already be dropping; the reconnect shows on the
          // Connection screen and in Diagnostics.
        }
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('สั่งรีสตาร์ตแล้ว กำลังเชื่อมต่อกลับ')),
        );
      },
    );
  }
}

/// Sent while a capture session opened (or nothing streams any more).
class _RefusedSheet extends StatelessWidget {
  const _RefusedSheet();

  @override
  Widget build(BuildContext context) {
    return ConfirmSheet(
      key: const ValueKey('command-refused'),
      title: 'ทำไม่ได้ตอนนี้',
      cancelLabel: 'ปิด',
      child: Text(
        'ทำไม่ได้ระหว่างเก็บข้อมูลวิจัย หรือเมื่อยังไม่ได้เชื่อมต่อแผ่นรองเท้า',
        style: AppText.secondary.copyWith(color: AppColors.ink),
      ),
    );
  }
}
