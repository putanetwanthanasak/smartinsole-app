import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/packets.dart';
import '../../capture/capture_providers.dart';
import '../../device/device_providers.dart';
import '../../device/insole_commands.dart';
import '../routes.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/back_link.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_sheet.dart';
import '../widgets/info_box.dart';
import '../widgets/list_row.dart';
import '../widgets/page_title.dart';
import 'connection/connection_providers.dart';
import 'researcher/researcher_model.dart';
import 'researcher/researcher_providers.dart';
import 'researcher/researcher_sheets.dart';

/// Researcher (DESIGN-SPEC §10.2, board SettingsDResearch): Settings ›
/// hold "ส่วนผู้วิจัย" 2 s. Thai like the board; the capture screens it
/// opens stay English (S4C). In release builds too.
class ResearcherScreen extends StatelessWidget {
  const ResearcherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = <Widget>[
      PageTitle('ส่วนผู้วิจัย'),
      WarningBox(
        text:
            'ใช้ระหว่างการทดสอบงานวิจัยเท่านั้น ผู้ใช้ทั่วไปไม่ต้องใช้ส่วนนี้',
      ),
      _CaptureCard(),
      _DeviceCard(),
      _DeviceInfoCard(),
      _DiagnosticsCard(),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('researcher-scroll'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pageTopPushed,
            Dimens.pagePadding,
            Dimens.pageBottomPushed,
          ),
          children: [
            const BackLink(),
            const SizedBox(height: Dimens.tightGap),
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: Dimens.sectionGap),
              sections[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A white card with a title (20/600), rows edge to edge, and an
/// optional footer line.
class _TitledCard extends StatelessWidget {
  const _TitledCard({
    required this.title,
    required this.children,
    this.footer,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.smallCardPadding,
                Dimens.smallCardPadding,
                Dimens.smallCardPadding,
                Dimens.tightGap,
              ),
              child: Semantics(
                header: true,
                child: Text(title, style: AppText.cardTitle),
              ),
            ),
            ...children,
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.smallCardPadding,
                  Dimens.tightGap,
                  Dimens.smallCardPadding,
                  Dimens.smallCardPadding,
                ),
                child: Text(footer!, style: AppText.secondary),
              ),
          ],
        ),
      ),
    );
  }
}

const _rowDivider = Divider(
  height: Dimens.dividerWidth,
  thickness: Dimens.dividerWidth,
  color: AppColors.divider,
);

/// "เก็บข้อมูลวิจัย": the readiness checks, "เริ่มเก็บข้อมูลวิจัย" (the S4C
/// flow, unchanged) and the export row. Rebuilt from the 10 Hz snapshot so
/// the checks are read at read time (rule 2).
class _CaptureCard extends ConsumerWidget {
  const _CaptureCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(displaySnapshotProvider).value;
    final meter = ref.watch(sampleRateMeterProvider);
    final checks = readinessChecks(snap, meter.rate);
    final ready = checks.every((c) => c.ok);
    final sessions = ref.watch(researchSessionsProvider).value ?? const [];
    void openCapture() => Navigator.pushNamed(
      context,
      Routes.capture,
    ).then((_) => ref.invalidate(researchSessionsProvider));

    return _TitledCard(
      key: const ValueKey('researcher-capture'),
      title: 'เก็บข้อมูลวิจัย',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Dimens.smallCardPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in checks.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimens.tightGap),
                  child: MergeSemantics(
                    child: Row(
                      key: ValueKey('readiness-$i'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          c.ok
                              ? LucideIcons.circle_check
                              : LucideIcons.triangle_alert,
                          size: Dimens.iconButtonIcon,
                          color: c.ok
                              ? StatusColors.safe.icon
                              : StatusColors.careful.icon,
                          semanticLabel: c.ok ? 'ผ่าน' : 'ยังไม่ผ่าน',
                        ),
                        const SizedBox(width: Dimens.buttonGap),
                        Expanded(
                          child: Text(
                            c.text,
                            style: AppText.secondary.copyWith(
                              color: c.ok
                                  ? AppColors.ink
                                  : StatusColors.careful.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: Dimens.tightGap),
              PrimaryButton(
                key: const ValueKey('start-capture'),
                label: 'เริ่มเก็บข้อมูลวิจัย',
                icon: LucideIcons.flask_conical,
                onPressed: ready ? openCapture : null,
              ),
              const SizedBox(height: Dimens.cardGap),
            ],
          ),
        ),
        _rowDivider,
        // Always opens, so exports, resume and the test-data clear stay
        // reachable when the checks fail (user decision 6A).
        ListRow(
          key: const ValueKey('researcher-export'),
          icon: LucideIcons.folder_output,
          title: 'ส่งออกไฟล์',
          value: exportLine(sessions),
          onTap: openCapture,
        ),
      ],
    );
  }
}

/// "อุปกรณ์": TARE and reboot, both disabled while a research capture
/// session is open (BACKLOG 21) or nothing is connected.
class _DeviceCard extends ConsumerWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-evaluated when a capture opens or closes, and at 10 Hz for the
    // links.
    ref.watch(activeCaptureProvider);
    ref.watch(displaySnapshotProvider);
    final refusal = ref.watch(insoleCommandsProvider).refusal;
    final enabled = refusal == null;
    String value(String normal) => refusal == CommandRefusal.notConnected
        ? 'เชื่อมต่อแผ่นรองเท้าก่อน'
        : normal;

    return _TitledCard(
      key: const ValueKey('researcher-device'),
      title: 'อุปกรณ์',
      footer: 'ทั้งสองอย่างทำไม่ได้ระหว่างเก็บข้อมูลวิจัย',
      children: [
        ListRow(
          key: const ValueKey('researcher-tare'),
          icon: LucideIcons.gauge,
          title: 'ตั้งค่าศูนย์เซนเซอร์ (TARE)',
          value: value('ยกเท้าออกจากแผ่นรองเท้าก่อน'),
          tone: enabled ? RowTone.normal : RowTone.locked,
          onTap: enabled
              ? () => showConfirmSheet<void>(context, const TareSheet())
              : null,
        ),
        _rowDivider,
        ListRow(
          key: const ValueKey('researcher-reboot'),
          icon: LucideIcons.power,
          title: 'รีสตาร์ตแผ่นรองเท้า',
          value: value('ใช้เมื่อแผ่นรองเท้าค้าง'),
          tone: enabled ? RowTone.normal : RowTone.locked,
          onTap: enabled
              ? () => showConfirmSheet<void>(context, const RebootSheet())
              : null,
        ),
      ],
    );
  }
}

/// "ข้อมูลอุปกรณ์": firmware, MTU and the measured data rate per foot.
class _DeviceInfoCard extends ConsumerWidget {
  const _DeviceInfoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(displaySnapshotProvider).value;
    final meter = ref.watch(sampleRateMeterProvider);
    final links = {
      for (final s in FootSide.values) s: ref.watch(linkStateProvider(s)).value,
    };
    final rows = [
      ('เฟิร์มแวร์', perFoot((s) => snap?.of(s).firmware)),
      (
        'ขนาดแพ็กเก็ต (MTU)',
        agreedOrPerFoot((s) {
          final l = links[s];
          return l == null ? null : mtuOf(l)?.toString();
        }),
      ),
      (
        'อัตราข้อมูล',
        agreedOrPerFoot(
          (s) => meter.rate(s)?.toStringAsFixed(0),
          unit: ' ครั้ง/วินาที',
          bothNote: ' ต่อข้าง',
        ),
      ),
    ];
    return _TitledCard(
      key: const ValueKey('researcher-info'),
      title: 'ข้อมูลอุปกรณ์',
      children: [
        for (final (label, value) in rows) ...[
          _rowDivider,
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.smallCardPadding,
              vertical: Dimens.buttonGap,
            ),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.secondary),
                  Text(value, style: AppText.labelStrong),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Diagnostics: the S3A BLE debug screen, reachable only from here (S8B,
/// user decision 7A). Storage counts, the Gait model check, the timing
/// check, the reconnect record and the event log, in release builds too.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    return _TitledCard(
      key: const ValueKey('researcher-diagnostics'),
      title: 'ตรวจสอบระบบ',
      children: [
        _rowDivider,
        ListRow(
          key: const ValueKey('diagnostics-row'),
          icon: LucideIcons.monitor_cog,
          title: 'Diagnostics',
          value:
              'การเชื่อมต่อ การเชื่อมต่อกลับ ข้อมูลในเครื่อง '
              'โมเดลท่าเดิน และการตรวจเวลา',
          onTap: () => Navigator.pushNamed(context, Routes.bleDebug),
        ),
      ],
    );
  }
}
