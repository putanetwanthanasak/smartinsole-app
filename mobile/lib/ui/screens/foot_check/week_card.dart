import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../footcheck/compare_source.dart';
import '../../../storage/models.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/foot_map.dart';
import 'foot_check_copy.dart';

/// What one day of the 7-day row shows.
enum DayMark { saved, found, missed }

DayMark dayMarkOf(FootCheck? latest) => switch (latest?.result) {
  null => DayMark.missed,
  FootCheckResult.saved => DayMark.saved,
  FootCheckResult.found => DayMark.found,
};

/// Card "7 วันที่ผ่านมา" (DESIGN-SPEC §11.5 item 4): 7 columns, oldest
/// first; today's abbreviation is 700 in an `outline` frame. Saved =
/// `primarySoft` + `check`; found = Be-careful + `triangle-alert`; missed
/// = a dashed `inkSubtle` ring. Each day's latest check counts.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.dates, required this.marks});

  /// `YYYY-MM-DD`, oldest first; the last is today.
  final List<String> dates;
  final List<DayMark> marks;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(FootCheckCopy.weekTitle, style: AppText.cardTitle),
          const SizedBox(height: Dimens.cardGap),
          Semantics(
            label: FootCheckCopy.weekLabel,
            role: SemanticsRole.list,
            container: true,
            explicitChildNodes: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < dates.length; i++) ...[
                  if (i > 0) const SizedBox(width: Dimens.weekDayGap),
                  Expanded(
                    child: _Day(
                      date: dates[i],
                      mark: marks[i],
                      today: i == dates.length - 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Dimens.cardGap),
          const ExcludeSemantics(
            child: Wrap(
              spacing: Dimens.cardGap,
              runSpacing: Dimens.tightGap,
              children: [
                _Legend(mark: DayMark.saved, label: FootCheckCopy.daySaved),
                _Legend(mark: DayMark.found, label: FootCheckCopy.dayFound),
                _Legend(mark: DayMark.missed, label: FootCheckCopy.dayMissed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _markWord(DayMark m) => switch (m) {
  DayMark.saved => FootCheckCopy.daySaved,
  DayMark.found => FootCheckCopy.dayFound,
  DayMark.missed => FootCheckCopy.dayMissed,
};

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.mark, required this.today});

  final String date;
  final DayMark mark;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final abbr = FootCheckCopy.weekdayShort(localDateTimeOf(date));
    final label = [
      if (today) FootCheckCopy.today,
      abbr,
      _markWord(mark),
    ].join(' ');
    return Semantics(
      label: label,
      role: SemanticsRole.listItem,
      container: true,
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: Dimens.textGap,
              horizontal: Dimens.textGap,
            ),
            decoration: today
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(Dimens.radiusInner),
                    border: Border.all(
                      color: AppColors.outline,
                      width: Dimens.outlineWidth,
                    ),
                  )
                : null,
            child: Text(
              abbr,
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(
                color: AppColors.ink,
                fontWeight: today ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: Dimens.tightGap),
          DayMarkCircle(mark: mark, size: Dimens.weekCircle),
        ],
      ),
    );
  }
}

/// The 7-day row's circle (also its legend, smaller).
class DayMarkCircle extends StatelessWidget {
  const DayMarkCircle({super.key, required this.mark, required this.size});

  final DayMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = size / 2;
    return SizedBox.square(
      dimension: size,
      child: switch (mark) {
        DayMark.saved => DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.check, size: icon, color: AppColors.primary),
        ),
        DayMark.found => DecoratedBox(
          decoration: BoxDecoration(
            color: StatusColors.careful.background,
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.triangle_alert,
            size: icon,
            color: StatusColors.careful.icon,
          ),
        ),
        DayMark.missed => const CustomPaint(painter: _MissedRing()),
      },
    );
  }
}

class _MissedRing extends CustomPainter {
  const _MissedRing();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - Dimens.weekMissedRing / 2;
    final path = Path()
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: r));
    canvas.drawPath(
      dashedPath(path, Dimens.weekMissedDash),
      Paint()
        ..color = AppColors.inkSubtle
        ..style = PaintingStyle.stroke
        ..strokeWidth = Dimens.weekMissedRing,
    );
  }

  @override
  bool shouldRepaint(_MissedRing old) => false;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.mark, required this.label});

  final DayMark mark;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DayMarkCircle(mark: mark, size: Dimens.legendCircle),
      const SizedBox(width: Dimens.textGap * 2),
      Text(label, style: AppText.secondary),
    ],
  );
}
