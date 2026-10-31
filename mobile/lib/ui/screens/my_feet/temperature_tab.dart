import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../rules/alert_copy.dart' show formatDelta, nbsp, sideTh;
import '../../../storage/models.dart';
import '../../../storage/storage_providers.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/details_expander.dart';
import '../../widgets/temp_delta_chart.dart';
import '../../widgets/temp_site_map.dart';
import 'my_feet_copy.dart';
import 'my_feet_model.dart';
import 'my_feet_widgets.dart';
import 'temp_chart_model.dart';

/// Today's stored readings, both feet, oldest first (`watchDay` of the
/// local date at [TempTabView.minute]).
final _todayReadingsProvider = Provider.autoDispose<List<TemperatureReading>>((
  ref,
) {
  final minute = ref.watch(myFeetViewProvider.select((v) => v.temp.minute));
  final date = ref.watch(localDatesProvider).of(minute.millisecondsSinceEpoch);
  return ref.watch(dayTemperaturesProvider(date)).value ?? const [];
});

/// When each foot's data stopped: its newest sample in this run, or its
/// newest stored reading today.
Map<FootSide, DateTime?> _sinceOf(
  TempTabView v,
  List<TemperatureReading> readings,
) => {
  for (final side in FootSide.values)
    side: v.foot(side).usable
        ? null
        : v.foot(side).lastDataAt ?? _lastStored(readings, side),
};

DateTime? _lastStored(List<TemperatureReading> readings, FootSide side) {
  for (final r in readings.reversed) {
    if (r.side == side) return DateTime.fromMillisecondsSinceEpoch(r.atMs);
  }
  return null;
}

DateTime? _latestOf(List<TemperatureReading> readings) => readings.isEmpty
    ? null
    : DateTime.fromMillisecondsSinceEpoch(readings.last.atMs);

/// My feet › "อุณหภูมิ" (DESIGN-SPEC §8.2, layout A): banner, the map card
/// (both feet's 8 sites and the top 3), today's chart (one line, the
/// largest |ΔT| of the 8 sites), and the table and rows behind
/// "ดูตัวเลขละเอียด". Two-foot values are "—" unless both feet stream
/// (rule 4).
class TemperatureTab extends ConsumerWidget {
  const TemperatureTab({super.key, required this.drawInKey});

  /// Changes each time the bottom-bar tab opens: the chart draws in again.
  final Object drawInKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(myFeetViewProvider.select((v) => v.temp));
    final readings = ref.watch(_todayReadingsProvider);
    final t = ref.watch(thresholdsProvider);
    final since = _sinceOf(v, readings);
    final latest = _latestOf(readings);
    final table = tempTable(v);
    return Column(
      key: const ValueKey('temperature-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFeetBanner(
          view: tempBanner(v, latestAt: latest, since: since),
        ),
        const SizedBox(height: Dimens.sectionGap),
        _MapCard(view: v),
        const SizedBox(height: Dimens.sectionGap),
        _ChartCard(view: v, readings: readings, drawInKey: drawInKey),
        const SizedBox(height: Dimens.sectionGap),
        DetailsExpander(
          key: const ValueKey('temperature-details'),
          leading: table.isEmpty ? null : _TempTable(rows: table),
          rows: tempDetailRows(v, t, latestAt: latest, since: since),
        ),
      ],
    );
  }
}

/// "ความอุ่นซ้าย–ขวา ตอนนี้" (§8.2, layout A): both feet with their 8
/// sites, the legend, then "จุดที่ต่างกันมากที่สุดตอนนี้" with the top 3.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.view});

  final TempTabView view;

  @override
  Widget build(BuildContext context) {
    final sites = tempSites(view);
    final top = topSites(view);
    final empty = topSitesEmptyLine(view);
    return AppCard(
      key: const ValueKey('temp-map-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ความอุ่นซ้าย–ขวา ตอนนี้', style: AppText.cardTitle),
          const SizedBox(height: Dimens.cardGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final side in FootSide.values) ...[
                if (side == FootSide.right)
                  const SizedBox(width: Dimens.feetFootGap),
                Column(
                  children: [
                    TempSiteMap(
                      key: ValueKey('temp-map-${side.name}'),
                      side: side,
                      marks: [for (final s in sites) s.markOn(side)],
                      semanticLabel: tempMapLabel(side, sites),
                      width: Dimens.feetFootWidth,
                      height: Dimens.feetFootHeight,
                      dashedOutline: !view.foot(side).usable,
                    ),
                    const SizedBox(height: Dimens.tightGap),
                    ExcludeSemantics(
                      child: Text(
                        sideTh(side),
                        style: AppText.labelStrong.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: Dimens.cardGap),
          const TempSiteLegend(
            textStyle: AppText.secondary,
            items: [
              (TempSiteMark.warm, 'จุดที่อุ่นกว่า'),
              (TempSiteMark.plain, 'ใกล้เคียงกัน'),
              (TempSiteMark.unreadable, 'ยังวัดไม่ได้'),
            ],
          ),
          const SizedBox(height: Dimens.cardGap),
          if (empty != null)
            Text(
              empty,
              key: const ValueKey('temp-top-empty'),
              style: AppText.labelStrong.copyWith(color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            )
          else ...[
            Text(
              'จุดที่ต่างกันมากที่สุดตอนนี้',
              style: AppText.labelStrong.copyWith(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Dimens.tightGap),
            for (final s in top) _SiteRow(view: s),
          ],
        ],
      ),
    );
  }
}

/// One row of "จุดที่ต่างกันมากที่สุดตอนนี้": dot, site over note, and
/// "{x.x}°" (the Rest colour with `octagon-alert` while `TEMP_DELTA`
/// holds there).
class _SiteRow extends StatelessWidget {
  const _SiteRow({required this.view});

  final TempSiteView view;

  @override
  Widget build(BuildContext context) {
    final rest = StatusColors.rest;
    final d = view.deltaC!;
    return MergeSemantics(
      child: Container(
        key: ValueKey('temp-row-${footLayout.zones[view.site].id}'),
        padding: const EdgeInsets.symmetric(vertical: Dimens.detailRowPaddingV),
        decoration: topDivider,
        child: Row(
          children: [
            SizedBox(
              width: FootDotColors.high.radius * Dimens.zoneRowDotScale * 2,
              child: Center(
                child: TempSiteDot(
                  mark: view.rowMark,
                  radius: TempSiteColors.radius * Dimens.zoneRowDotScale,
                ),
              ),
            ),
            const SizedBox(width: Dimens.buttonGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(view.siteTh, style: AppText.bodyStrong),
                  Text(view.note, style: AppText.secondary),
                ],
              ),
            ),
            const SizedBox(width: Dimens.tightGap),
            if (view.alerting) ...[
              Icon(
                LucideIcons.octagon_alert,
                size: Dimens.tagIcon,
                color: rest.icon,
              ),
              const SizedBox(width: Dimens.textGap),
            ],
            Semantics(
              label: '${formatDelta(d)}$nbspองศา',
              excludeSemantics: true,
              child: Text(
                '${formatDelta(d)}°',
                style: AppText.labelStrong.copyWith(
                  fontWeight: FontWeight.w700,
                  color: view.alerting ? rest.text : AppColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends ConsumerWidget {
  const _ChartCard({
    required this.view,
    required this.readings,
    required this.drawInKey,
  });

  final TempTabView view;
  final List<TemperatureReading> readings;
  final Object drawInKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(thresholdsProvider);
    final data = tempChartOf(
      readings,
      now: view.minute,
      usable: {for (final s in FootSide.values) s: view.foot(s).usable},
    );
    return AppCard(
      key: const ValueKey('temp-chart-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ความต่างของความอุ่นวันนี้', style: AppText.cardTitle),
          const SizedBox(height: Dimens.cardGap),
          Stack(
            alignment: Alignment.center,
            children: [
              TempDeltaChart(
                key: const ValueKey('temp-chart'),
                data: data,
                deltaC: t.deltaC,
                semanticLabel: chartSummary(data, deltaC: t.deltaC),
                drawInKey: drawInKey,
              ),
              if (data.isEmpty)
                ExcludeSemantics(
                  child: Text(
                    'ยังไม่มีข้อมูลวันนี้',
                    style: AppText.labelStrong.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Dimens.buttonGap),
          // S8D-2 draft (user decision 2026-10-31, Appendix A): the line can
          // switch sites; the alert counts each site on its own (rule 6).
          Text(
            tempChartNote(t.consecutiveReadings),
            key: const ValueKey('temp-chart-note'),
            style: AppText.secondary,
          ),
        ],
      ),
    );
  }
}

/// "อุณหภูมิตอนนี้ (°C)": sites down, "ซ้าย" / "ขวา" / "ต่าง" across,
/// numbers right-aligned with tabular figures (§8.2, modelled on
/// Pressure's kPa table). The number columns are at least 52 px and grow
/// with the text so "31.0" never breaks at large text; the site column
/// takes the rest and wraps.
class _TempTable extends StatelessWidget {
  const _TempTable({required this.rows});

  final List<TempTableRow> rows;

  static const _minColumn = 52.0;

  @override
  Widget build(BuildContext context) {
    const numbers = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    final value = AppText.labelStrong.merge(numbers);
    const cellPadding = EdgeInsets.symmetric(vertical: Dimens.textGap * 2);
    TableRow row(TempTableRow r, {bool header = false}) {
      final style = header ? AppText.secondary : value;
      return TableRow(
        decoration: header ? null : topDivider,
        children: [
          Padding(
            padding: cellPadding,
            child: Text(
              r.site,
              style: header ? AppText.secondary : AppText.labelStrong,
            ),
          ),
          for (final v in [r.left, r.right, r.delta])
            Padding(
              padding: cellPadding.copyWith(left: Dimens.tightGap),
              child: Text(
                v,
                style: style,
                textAlign: TextAlign.end,
                softWrap: false,
              ),
            ),
        ],
      );
    }

    const number = MaxColumnWidth(
      FixedColumnWidth(_minColumn),
      IntrinsicColumnWidth(),
    );
    return Container(
      key: const ValueKey('temp-table'),
      padding: const EdgeInsets.only(bottom: Dimens.tightGap),
      decoration: topDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Dimens.detailRowPaddingV),
          Text('อุณหภูมิตอนนี้ (°C)', style: AppText.secondary),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: number,
              2: number,
              3: number,
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              row(
                const TempTableRow('จุด', 'ซ้าย', 'ขวา', 'ต่าง'),
                header: true,
              ),
              for (final r in rows) row(r),
            ],
          ),
        ],
      ),
    );
  }
}
