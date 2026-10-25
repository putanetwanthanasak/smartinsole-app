import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/packets.dart';
import '../../capture/capture_providers.dart';
import '../../config/thresholds.dart';
import '../../device/device_providers.dart';
import '../../device/display_snapshot.dart';
import '../../device/mock_data_source.dart';
import '../../settings/app_settings.dart';
import '../../settings/settings_providers.dart';
import '../../storage/sample_alerts.dart';
import '../../storage/sample_day.dart';
import '../../storage/storage_providers.dart';
import '../clock.dart';
import '../routes.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/back_link.dart';
import '../widgets/confirm_sheet.dart';
import '../widgets/list_row.dart';
import '../widgets/page_title.dart';

/// Settings (DESIGN-SPEC §10.1). Every value persists across restarts
/// (`lib/settings/`); the researcher's test-data clear never resets them.
/// The BLE debug screen is no longer reachable from here: it is
/// Researcher › Diagnostics (S8B, user decision 7A).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only in a debug run started with --dart-define=MOCK=<preset>.
    final mock = ref.watch(mockInsolesProvider);
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final photos = ref.watch(footPhotoCountProvider).value ?? 0;

    final sections = <Widget>[
      const PageTitle('ตั้งค่า'),
      SettingsGroup(
        label: 'ข้อมูลของคุณ',
        rows: [
          ListRow(
            key: const ValueKey('settings-name'),
            icon: LucideIcons.user,
            title: 'ชื่อที่ใช้ทักทาย',
            value: s.greetingName ?? SettingsCopy.noName,
            valueKey: const ValueKey('settings-name-value'),
            onTap: () => showConfirmSheet<void>(
              context,
              _NameSheet(initial: s.greetingName ?? '', onSave: c.setName),
            ),
          ),
        ],
      ),
      SettingsGroup(
        label: 'การแสดงผล',
        rows: [_TextSizeCard(selected: s.textSize, onSelect: c.setTextSize)],
      ),
      SettingsGroup(
        label: 'การแจ้งเตือน',
        rows: [
          ListRow(
            icon: LucideIcons.volume_2,
            title: 'เสียงแจ้งเตือน',
            trailing: AppSwitch(
              key: const ValueKey('settings-sound'),
              value: s.sound,
              label: 'เสียงแจ้งเตือน',
              onChanged: c.setSound,
            ),
          ),
          ListRow(
            icon: LucideIcons.camera,
            title: 'เตือนให้ดูเท้าทุกวัน',
            trailing: AppSwitch(
              key: const ValueKey('settings-reminder'),
              value: s.footCheckReminder,
              label: 'เตือนให้ดูเท้าทุกวัน',
              onChanged: c.setFootCheckReminder,
            ),
          ),
          ListRow(
            key: const ValueKey('settings-reminder-time'),
            icon: LucideIcons.clock,
            title: 'เวลาเตือน',
            value: 'ทุกวัน ${formatReminderTime(s.reminderTime)}',
            valueKey: const ValueKey('settings-reminder-time-value'),
            onTap: () => _pickTime(context, s.reminderTime, c),
          ),
        ],
      ),
      SettingsGroup(
        label: 'แผ่นรองเท้า',
        rows: [
          ListRow(
            key: const ValueKey('settings-connection'),
            icon: LucideIcons.bluetooth,
            title: 'เชื่อมต่อแผ่นรองเท้า',
            value: SettingsCopy.insoles(
              ref.watch(displaySnapshotProvider).value,
            ),
            onTap: () => Navigator.pushNamed(context, Routes.connection),
          ),
        ],
      ),
      SettingsGroup(
        label: 'ข้อมูลในเครื่องนี้',
        rows: [
          const _TextRow(icon: LucideIcons.lock, text: SettingsCopy.privacy),
          ListRow(
            key: const ValueKey('settings-delete-photos'),
            // Lucide 1.59 names "trash-2" (with the two lines) "trash".
            icon: LucideIcons.trash,
            title: 'ลบรูปถ่ายเท้าทั้งหมด',
            value: SettingsCopy.photoCount(photos),
            tone: RowTone.destructive,
            onTap: photos == 0
                ? null
                : () => showConfirmSheet<void>(
                    context,
                    _DeletePhotosSheet(count: photos),
                  ),
          ),
        ],
      ),
      const _ResearcherGroup(),
      const _AboutGroup(),
      if (mock != null) _MockPresetButton(mock: mock),
      if (mock != null) const _SeedAlertsButton(),
      if (mock != null) _SeedDayButton(mock: mock),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('settings-scroll'),
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

  /// The platform time picker, 24-hour (not designed; §14).
  static Future<void> _pickTime(
    BuildContext context,
    TimeOfDay initial,
    SettingsController c,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'เวลาเตือน',
      cancelText: 'ยกเลิก',
      confirmText: 'บันทึก',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) await c.setReminderTime(picked);
  }
}

/// Settings copy. Lines not on the SettingsD board are drafts (S8B).
abstract final class SettingsCopy {
  /// Draft: the name row before a name is set.
  static const noName = 'ยังไม่ได้ตั้งชื่อ';

  static const privacy =
      'ข้อมูลและรูปถ่ายเท้าเก็บไว้ในโทรศัพท์เครื่องนี้เท่านั้น ไม่ได้ส่งไปที่ไหน';

  static const about =
      'แอปนี้ช่วยดูแลเท้า ไม่ใช่เครื่องมือวินิจฉัยโรค ถ้ามีแผลหรืออาการผิดปกติ ให้ไปพบแพทย์';

  static const buildLabel = 'รุ่นทดสอบงานวิจัย';

  /// "ตอนนี้มี 28 รูป" (board); none is a draft.
  static String photoCount(int n) =>
      n == 0 ? 'ยังไม่มีรูปถ่ายเท้า' : 'ตอนนี้มี $n รูป';

  /// The Connection row's value: "เชื่อมต่อแล้วทั้งสองข้าง" (board); the
  /// one-foot and none lines are drafts.
  static String insoles(DisplaySnapshot? snap) {
    bool on(FootSide s) => snap?.of(s).connection == FootConnection.streaming;
    final l = on(FootSide.left);
    final r = on(FootSide.right);
    if (l && r) return 'เชื่อมต่อแล้วทั้งสองข้าง';
    if (l) return 'เชื่อมต่อแล้วเฉพาะเท้าซ้าย';
    if (r) return 'เชื่อมต่อแล้วเฉพาะเท้าขวา';
    return 'ยังไม่ได้เชื่อมต่อ';
  }
}

/// "ขนาดตัวอักษร" (§10.1): 3 options in a radio group, a preview box and
/// the note. The preview is written at 18 px; the app's text scaler makes
/// it 18 / 22 / 26 (times the phone's own scale).
class _TextSizeCard extends StatelessWidget {
  const _TextSizeCard({required this.selected, required this.onSelect});

  final TextSizeOption selected;
  final ValueChanged<TextSizeOption> onSelect;

  static const _optionHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: Dimens.listRowCircle,
                height: Dimens.listRowCircle,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.type,
                  size: Dimens.listRowIcon,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: Dimens.cardGap),
              const Expanded(
                child: Text('ขนาดตัวอักษร', style: AppText.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: Dimens.cardGap),
          Semantics(
            container: true,
            label: 'ขนาดตัวอักษร',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final o in TextSizeOption.values) ...[
                  if (o.index > 0) const SizedBox(width: Dimens.tightGap),
                  Expanded(child: _option(o)),
                ],
              ],
            ),
          ),
          const SizedBox(height: Dimens.cardGap),
          DecoratedBox(
            key: const ValueKey('text-size-preview'),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(Dimens.radiusInner),
            ),
            child: const Padding(
              padding: EdgeInsets.all(Dimens.smallCardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ตัวอย่าง', style: AppText.secondary),
                  Text('ตอนนี้เท้าปลอดภัย', style: AppText.textSizePreview),
                ],
              ),
            ),
          ),
          const SizedBox(height: Dimens.tightGap),
          const Text(
            'ใช้ร่วมกับขนาดตัวอักษรที่ตั้งไว้ในโทรศัพท์',
            style: AppText.secondary,
          ),
        ],
      ),
    );
  }

  Widget _option(TextSizeOption o) {
    final on = o == selected;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: o.label,
      excludeSemantics: true,
      onTap: () => onSelect(o),
      child: Material(
        color: on ? AppColors.primary : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusInner),
          side: on
              ? BorderSide.none
              : const BorderSide(
                  color: AppColors.outline,
                  width: Dimens.outlineWidth,
                ),
        ),
        child: InkWell(
          key: ValueKey('text-size-${o.name}'),
          borderRadius: BorderRadius.circular(Dimens.radiusInner),
          onTap: () => onSelect(o),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _optionHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.textGap,
                  vertical: Dimens.textGap,
                ),
                child: Text(
                  o.label,
                  textAlign: TextAlign.center,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    color: on ? AppColors.surface : AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of plain text with its icon circle (the privacy line).
class _TextRow extends StatelessWidget {
  const _TextRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.smallCardPadding,
        vertical: Dimens.buttonGap,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Dimens.listRowCircle,
            height: Dimens.listRowCircle,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: Dimens.listRowIcon,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: Dimens.cardGap),
          Expanded(
            child: Text(
              text,
              style: AppText.secondary.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// "เกี่ยวกับแอป": version and the app disclaimer.
class _AboutGroup extends ConsumerWidget {
  const _AboutGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroup(
      label: 'เกี่ยวกับแอป',
      rows: [
        Padding(
          padding: const EdgeInsets.all(Dimens.smallCardPadding),
          child: Wrap(
            spacing: Dimens.buttonGap,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text('เวอร์ชัน', style: AppText.bodyStrong),
              FutureBuilder<String>(
                future: ref.watch(appVersionProvider),
                builder: (context, snap) => Text(
                  '${snap.data ?? '—'} · ${SettingsCopy.buildLabel}',
                  key: const ValueKey('settings-version'),
                  style: AppText.secondary,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(Dimens.smallCardPadding),
          child: Text(SettingsCopy.about, style: AppText.secondary),
        ),
      ],
    );
  }
}

/// Name editor (not designed; §14): the confirmation sheet pattern with a
/// text field. Draft copy.
class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initial, required this.onSave});

  final String initial;
  final Future<void> Function(String?) onSave;

  static const maxLength = 30;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmSheet(
      title: 'ชื่อที่ใช้ทักทาย',
      text: 'หน้าวันนี้จะทักทายด้วยชื่อนี้ เว้นว่างไว้ได้ถ้าไม่ต้องการ',
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'บันทึก',
      onConfirm: () async {
        await widget.onSave(_controller.text);
        if (context.mounted) Navigator.pop(context);
      },
      child: TextField(
        key: const ValueKey('name-field'),
        controller: _controller,
        autofocus: true,
        style: AppText.body,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          LengthLimitingTextInputFormatter(_NameSheet.maxLength),
        ],
        decoration: const InputDecoration(hintText: 'เช่น สมชาย'),
      ),
    );
  }
}

/// "ลบรูปถ่ายเท้าทั้งหมด" confirmation (§14: the TARE sheet pattern).
/// Draft copy. Empties the photo folder; the foot-check answers stay.
class _DeletePhotosSheet extends ConsumerStatefulWidget {
  const _DeletePhotosSheet({required this.count});

  final int count;

  @override
  ConsumerState<_DeletePhotosSheet> createState() => _DeletePhotosSheetState();
}

class _DeletePhotosSheetState extends ConsumerState<_DeletePhotosSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ConfirmSheet(
      title: 'ลบรูปถ่ายเท้าทั้งหมด',
      text:
          'รูปถ่ายเท้า ${widget.count} รูปจะถูกลบออกจากโทรศัพท์เครื่องนี้ '
          'คำตอบที่บันทึกไว้ในการตรวจเท้ายังอยู่',
      warning: 'ลบแล้วนำรูปกลับมาไม่ได้',
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'ลบรูปทั้งหมด',
      onConfirm: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              final n = await ref.read(deleteFootPhotosProvider)();
              ref.invalidate(footPhotoCountProvider);
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              messenger.showSnackBar(
                SnackBar(content: Text('ลบรูปถ่ายเท้าแล้ว $n รูป')),
              );
            },
    );
  }
}

/// "สำหรับผู้วิจัย" group (DESIGN-SPEC §10.1): one row that opens the
/// Researcher screen only after a 2-second long press, so a patient cannot
/// open it by accident. TalkBack users trigger it with the long-press
/// action (double-tap and hold).
class _ResearcherGroup extends StatelessWidget {
  const _ResearcherGroup();

  /// How long the row must be held (§10.1). An input gate, not an
  /// animation.
  static const hold = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.pushNamed(context, Routes.researcher);
    return SettingsGroup(
      label: 'สำหรับผู้วิจัย',
      rows: [
        Semantics(
          button: true,
          label: 'ส่วนผู้วิจัย',
          hint: 'กดค้าง 2 วินาทีเพื่อเปิด',
          onLongPress: open,
          excludeSemantics: true,
          child: RawGestureDetector(
            key: const ValueKey('researcher-row'),
            // The whole row, not only its icon and text.
            behavior: HitTestBehavior.opaque,
            gestures: {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(duration: hold),
                    (r) => r.onLongPress = open,
                  ),
            },
            child: ListRow(
              icon: LucideIcons.lock,
              title: 'ส่วนผู้วิจัย',
              value: 'กดค้าง 2 วินาทีเพื่อเปิด',
              tone: RowTone.locked,
            ),
          ),
        ),
      ],
    );
  }
}

/// Debug builds with the mock only: switches the mock preset live, so
/// every Home state can be shown on the emulator without relaunching.
class _MockPresetButton extends StatelessWidget {
  const _MockPresetButton({required this.mock});

  final MockInsoles mock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mock,
      builder: (context, _) => OutlinedButton(
        key: const ValueKey('mock-preset-button'),
        onPressed: () => _pick(context),
        child: Text('Mock preset (debug): ${mock.preset.name}'),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<MockPreset>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in MockPreset.values)
              ListTile(
                key: ValueKey('mock-preset-${p.name}'),
                title: Text(p.name),
                trailing: p == mock.preset
                    ? const Icon(LucideIcons.check)
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) mock.preset = picked;
  }
}

/// Debug builds with the mock only (an in-memory database): writes one
/// alert of each listed kind with the design boards' values, for the
/// design screenshots (S6B). Not from the alert engine.
class _SeedAlertsButton extends ConsumerWidget {
  const _SeedAlertsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      key: const ValueKey('seed-alerts-button'),
      onPressed: () async {
        await seedSampleAlerts(
          alerts: ref.read(alertRepositoryProvider),
          footChecks: ref.read(footCheckRepositoryProvider),
          thresholds: ref.read(thresholdsProvider),
          now: ref.read(clockProvider)(),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Seeded sample alerts')));
      },
      child: const Text('Seed sample alerts (debug)'),
    );
  }
}

/// Debug builds with the mock only (an in-memory database): writes a day
/// of temperature readings shaped by the current preset, for the My feet
/// screenshots (S6B part 2, `seedSampleDay`).
class _SeedDayButton extends ConsumerWidget {
  const _SeedDayButton({required this.mock});

  final MockInsoles mock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      key: const ValueKey('seed-day-button'),
      onPressed: () async {
        final n = await seedSampleDay(
          temperatures: ref.read(temperatureRepositoryProvider),
          dates: ref.read(localDatesProvider),
          thresholds: ref.read(thresholdsProvider),
          preset: mock.preset,
          now: ref.read(clockProvider)(),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seeded $n temperature readings')),
        );
      },
      child: const Text('Seed sample day (debug)'),
    );
  }
}
