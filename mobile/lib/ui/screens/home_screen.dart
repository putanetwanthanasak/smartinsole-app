import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/packets.dart';
import '../../rules/patient_status.dart';
import '../clock.dart';
import '../motion.dart';
import '../routes.dart';
import '../shell/app_shell.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/buttons.dart';
import '../widgets/foot_check_card.dart';
import '../widgets/foot_map.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/status_card.dart';
import 'home/home_copy.dart';
import 'home/home_model.dart';

/// Home, "วันนี้" (DESIGN-SPEC §6, style D). Every section reads
/// [homeViewProvider] through `select`, so a 10 Hz snapshot only rebuilds
/// the section whose visible values changed.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          key: const ValueKey('home-scroll'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pageBottom,
          ),
          child: StaggeredEntrance(
            gap: Dimens.sectionGap,
            children: [
              _Header(date: thaiLongDate(now)),
              const _FootChips(),
              const _HomeStatusCard(),
              // Shown unconditionally until S8C adds "done today" logic.
              FootCheckCard(
                onTap: () => ref
                    .read(selectedTabProvider.notifier)
                    .select(AppTab.footCheck),
              ),
              const _PressureCard(),
              const _SmallCards(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: AppText.secondary),
              // No name until Settings can set one (S8B).
              Semantics(
                header: true,
                child: const Text('สวัสดี', style: AppText.pageTitle),
              ),
            ],
          ),
        ),
        const SizedBox(width: Dimens.cardGap),
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dimens.radiusCard),
            side: const BorderSide(
              color: AppColors.outline,
              width: Dimens.outlineWidth,
            ),
          ),
          child: IconButton(
            key: const ValueKey('settings-button'),
            icon: const Icon(LucideIcons.settings),
            tooltip: 'ตั้งค่า',
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Dimens.radiusCard),
              ),
            ),
            onPressed: () => Navigator.pushNamed(context, Routes.settings),
          ),
        ),
      ],
    );
  }
}

// --- Foot chips -------------------------------------------------------------

class _FootChips extends StatelessWidget {
  const _FootChips();

  @override
  Widget build(BuildContext context) {
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _FootChip(side: FootSide.left)),
          SizedBox(width: Dimens.gridGap),
          Expanded(child: _FootChip(side: FootSide.right)),
        ],
      ),
    );
  }
}

/// Foot chip (§6 item 2): a link to Connection.
class _FootChip extends ConsumerWidget {
  const _FootChip({required this.side});

  final FootSide side;

  static const _radius = BorderRadius.all(Radius.circular(Dimens.radiusCard));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chip = ref.watch(homeViewProvider.select((v) => v.chip(side)));
    final battery = chip.batteryPct;
    final Widget second;
    if (!chip.connected || battery == null) {
      second = const Text('ไม่ได้เชื่อมต่อ', style: AppText.secondary);
    } else if (chip.lowBattery) {
      // Low-battery style (§5, decision 10): dark amber text + icon.
      second = Row(
        children: [
          Icon(
            LucideIcons.battery_low,
            size: Dimens.inlineIcon,
            color: StatusColors.careful.icon,
          ),
          const SizedBox(width: Dimens.textGap),
          Flexible(
            child: Text(
              'แบต $battery%',
              style: AppText.secondary.copyWith(
                color: StatusColors.careful.text,
              ),
            ),
          ),
        ],
      );
    } else {
      second = Text('แบต $battery%', style: AppText.secondary);
    }

    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: AppColors.outline, width: Dimens.outlineWidth),
      ),
      child: InkWell(
        key: ValueKey('foot-${side.name}'),
        borderRadius: _radius,
        onTap: () => Navigator.pushNamed(context, Routes.connection),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.footChipHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.smallCardPadding,
              vertical: Dimens.buttonGap,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ChipDot(connected: chip.connected),
                    const SizedBox(width: Dimens.tightGap),
                    Expanded(
                      child: Text(
                        'เท้า${sideTh(side)}',
                        style: AppText.bodyStrong,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: Dimens.chipIndent),
                  child: second,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 12 px dot: filled `connected` when connected, a hollow `inkSubtle` ring
/// when not; the colour change uses `enter`.
class _ChipDot extends StatelessWidget {
  const _ChipDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.duration(context, Motion.enterDuration),
      curve: Motion.enter,
      width: Dimens.chipDot,
      height: Dimens.chipDot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected
            ? AppColors.connected
            : AppColors.connected.withValues(alpha: 0),
        border: Border.all(
          color: connected ? AppColors.connected : AppColors.inkSubtle,
          width: Dimens.chipDotRing,
        ),
      ),
    );
  }
}

// --- Status card ------------------------------------------------------------

class _HomeStatusCard extends ConsumerWidget {
  const _HomeStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(homeViewProvider.select((v) => v.status));
    final copy = statusCopy(status);
    return StatusCard(
      key: const ValueKey('status-card'),
      level: status.level,
      title: copy.title,
      detail: copy.detail,
      advice: copy.advice,
      action: status.level == PatientLevel.noData
          ? PrimaryButton(
              key: const ValueKey('connect-button'),
              label: 'เชื่อมต่อแผ่นรองเท้า',
              icon: LucideIcons.bluetooth,
              onPressed: () => Navigator.pushNamed(context, Routes.connection),
            )
          : null,
    );
  }
}

// --- Pressure card ----------------------------------------------------------

class _PressureCard extends ConsumerWidget {
  const _PressureCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maps = ref.watch(
      homeViewProvider.select((v) => (v.leftMap, v.rightMap)),
    );
    final (caption, warning) = mapCaption(maps.$1, maps.$2);

    return AppCard(
      key: const ValueKey('pressure-card'),
      padding: const EdgeInsets.fromLTRB(
        Dimens.cardPadding,
        Dimens.cardPadding,
        Dimens.cardPadding,
        Dimens.tightGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('น้ำหนักที่เท้ารับอยู่ตอนนี้', style: AppText.cardTitle),
          const SizedBox(height: Dimens.cardGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabelledFoot(map: maps.$1),
              const SizedBox(width: Dimens.homeFootGap),
              _LabelledFoot(map: maps.$2),
            ],
          ),
          const SizedBox(height: Dimens.cardGap),
          _Caption(text: caption, warning: warning),
          const SizedBox(height: Dimens.buttonGap),
          const PressureLegend(textStyle: AppText.secondary),
          const SizedBox(height: Dimens.cardGap),
          const _SeeMoreRow(),
        ],
      ),
    );
  }
}

class _LabelledFoot extends StatelessWidget {
  const _LabelledFoot({required this.map});

  final FootMapView map;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FootMap(
          key: ValueKey('map-${map.side.name}'),
          side: map.side,
          levels: map.levels,
          semanticLabel: mapLabel(map),
          width: Dimens.homeFootWidth,
          height: Dimens.homeFootHeight,
        ),
        const SizedBox(height: Dimens.tightGap),
        ExcludeSemantics(
          child: Text(
            sideTh(map.side),
            style: AppText.labelStrong.copyWith(color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}

/// One-line caption: `ink`, or the Be-careful text colour with a warning
/// icon when a zone is high.
class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.warning});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final style = AppText.labelStrong.copyWith(
      color: warning ? StatusColors.careful.text : AppColors.ink,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (warning) ...[
          Icon(
            LucideIcons.triangle_alert,
            size: Dimens.smallCardIcon,
            color: StatusColors.careful.icon,
          ),
          const SizedBox(width: Dimens.tightGap),
        ],
        Flexible(
          child: Text(text, style: style, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// "ดูเพิ่ม" row: opens My feet › "แรงกด".
class _SeeMoreRow extends ConsumerWidget {
  const _SeeMoreRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = AppText.labelStrong.copyWith(color: AppColors.primary);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: InkWell(
        key: const ValueKey('see-more'),
        onTap: () => openMyFeet(context, ref, MyFeetTab.pressure),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.linkRowHeight),
          child: Row(
            children: [
              Expanded(child: Text('ดูเพิ่ม', style: style)),
              const Icon(
                LucideIcons.chevron_right,
                size: Dimens.iconButtonIcon,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Small cards ------------------------------------------------------------

/// Temperature and balance (§6 item 6): two columns, stacked when the text
/// is so large that a 36 px number would not fit half the width.
class _SmallCards extends StatelessWidget {
  const _SmallCards();

  /// Above this text scale the two cards stack (nothing may clip, §13).
  static const _stackAboveScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale > _stackAboveScale) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TempCard(),
          SizedBox(height: Dimens.gridGap),
          _BalanceCard(),
        ],
      );
    }
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _TempCard()),
          SizedBox(width: Dimens.gridGap),
          Expanded(child: _BalanceCard()),
        ],
      ),
    );
  }
}

class _SmallCard extends StatelessWidget {
  const _SmallCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: Dimens.smallCardIcon, color: AppColors.outline),
              const SizedBox(width: Dimens.tightGap),
              Expanded(child: Text(title, style: AppText.labelStrong)),
            ],
          ),
          for (final c in children) ...[
            const SizedBox(height: Dimens.tightGap),
            c,
          ],
        ],
      ),
    );
  }
}

/// "—" in `inkMuted`, with "ต้องเชื่อมต่อทั้งสองข้าง" unless both feet are
/// connected (rule 4).
List<Widget> _noValue({required bool needBoth}) => [
  Text('—', style: AppText.bigNumber.copyWith(color: AppColors.inkMuted)),
  if (needBoth) const Text(needBothFeet, style: AppText.secondary),
];

/// A plain-Thai note, in a status text colour with its icon when it warns.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.palette, this.icon});

  final String text;
  final StatusPalette? palette;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = AppText.labelStrong.copyWith(color: palette?.text);
    if (palette == null || icon == null) return Text(text, style: style);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: Dimens.smallCardIcon, color: palette!.icon),
        const SizedBox(width: Dimens.textGap),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class _TempCard extends ConsumerWidget {
  const _TempCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (delta, note, alert) = ref.watch(
      homeViewProvider.select(
        (v) => (v.deltaC, v.deltaC == null ? '' : tempNote(v), v.tempAlert),
      ),
    );
    return _SmallCard(
      key: const ValueKey('temp-card'),
      icon: LucideIcons.thermometer,
      title: 'ความอุ่นของเท้า',
      children: delta == null
          ? _noValue(needBoth: true)
          : [
              Semantics(
                label: '${formatDelta(delta)} องศา',
                excludeSemantics: true,
                child: AnimatedNumber(
                  value: delta,
                  format: (v) => '${formatDelta(v)}°',
                  style: AppText.bigNumber,
                ),
              ),
              const Text('ต่างกันซ้าย–ขวา', style: AppText.secondary),
              alert
                  ? _Note(
                      text: note,
                      palette: StatusColors.rest,
                      icon: LucideIcons.octagon_alert,
                    )
                  : _Note(text: note),
            ],
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (share, note, noLoad, asymmetry) = ref.watch(
      homeViewProvider.select(
        (v) => (
          v.leftSharePct,
          v.leftSharePct == null ? '' : balanceNote(v),
          v.balanceNoLoad,
          v.asymmetrySide != null,
        ),
      ),
    );
    return _SmallCard(
      key: const ValueKey('balance-card'),
      icon: LucideIcons.scale,
      title: 'การลงน้ำหนัก',
      children: share == null
          ? _noValue(needBoth: !noLoad)
          : [
              Semantics(
                label: 'ซ้าย $share ขวา ${100 - share}',
                excludeSemantics: true,
                child: AnimatedNumber(
                  value: share.toDouble(),
                  format: (v) => '${v.round()} : ${100 - v.round()}',
                  style: AppText.bigNumber,
                ),
              ),
              _BalanceBar(leftSharePct: share.toDouble()),
              // Orange with an icon only while ASYMMETRY_PEAK holds (user
              // decision 2026-10-23, BACKLOG 37).
              asymmetry
                  ? _Note(
                      text: note,
                      palette: StatusColors.careful,
                      icon: LucideIcons.triangle_alert,
                    )
                  : _Note(text: note),
            ],
    );
  }
}

/// Bar 10 tall, radius 5: left share `primary`, right `accentLight`, track
/// `track`, a 2×16 `ink` centre tick; "ซ้าย"/"ขวา" under its ends. Slides
/// to a new value with `value`.
class _BalanceBar extends StatelessWidget {
  const _BalanceBar({required this.leftSharePct});

  final double leftSharePct;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          SizedBox(
            height: Dimens.balanceTickHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: leftSharePct / 100),
              duration: Motion.duration(context, Motion.valueDuration),
              curve: Motion.value,
              builder: (context, left, _) => CustomPaint(
                size: Size.infinite,
                painter: _BalancePainter(left: left),
              ),
            ),
          ),
          const SizedBox(height: Dimens.textGap),
          const Row(
            children: [
              Expanded(child: Text('ซ้าย', style: AppText.secondary)),
              Text('ขวา', style: AppText.secondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter({required this.left});

  /// Left share, 0–1.
  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    const h = Dimens.balanceBarHeight;
    final top = (size.height - h) / 2;
    final bar = RRect.fromLTRBR(
      0,
      top,
      size.width,
      top + h,
      const Radius.circular(h / 2),
    );
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRRect(bar, Paint()..color = AppColors.track)
      ..drawRect(
        Rect.fromLTWH(0, top, size.width * left, h),
        Paint()..color = AppColors.primary,
      )
      ..drawRect(
        Rect.fromLTRB(size.width * left, top, size.width, top + h),
        Paint()..color = AppColors.accentLight,
      )
      ..restore()
      ..drawRect(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: Dimens.balanceTickWidth,
          height: Dimens.balanceTickHeight,
        ),
        Paint()..color = AppColors.ink,
      );
  }

  @override
  bool shouldRepaint(_BalancePainter old) => old.left != left;
}
