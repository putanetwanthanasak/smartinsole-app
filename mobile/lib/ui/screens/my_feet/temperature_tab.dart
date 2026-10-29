import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../rules/alert_copy.dart' show formatDelta, nbsp;
import '../../../storage/models.dart';
import '../../../storage/storage_providers.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/details_expander.dart';
import '../../widgets/motion_widgets.dart';
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

/// My feet › "อุณหภูมิ" (DESIGN-SPEC §8.2): banner, the two site cards,
/// today's chart, and the numbers behind "ดูตัวเลขละเอียด". Two-foot values
/// are "—" unless both feet stream (rule 4).
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
    return Column(
      key: const ValueKey('temperature-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFeetBanner(
          view: tempBanner(v, latestAt: latest, since: since),
        ),
        const SizedBox(height: Dimens.sectionGap),
        TwoColumns(
          left: _SiteCard(view: siteCard(v, v.shownSites.first, t)),
          right: _SiteCard(view: siteCard(v, v.shownSites.last, t)),
        ),
        const SizedBox(height: Dimens.sectionGap),
        _ChartCard(view: v, readings: readings, drawInKey: drawInKey),
        const SizedBox(height: Dimens.sectionGap),
        DetailsExpander(
          key: const ValueKey('temperature-details'),
          rows: tempDetailRows(v, t, latestAt: latest, since: since),
        ),
      ],
    );
  }
}

/// One site card (§8.2): icon with the site dot, site name, the difference
/// (36/700), "ต่างกันซ้าย–ขวา", and the note.
class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.view});

  final SiteCardView view;

  @override
  Widget build(BuildContext context) {
    final rest = StatusColors.rest;
    final d = view.deltaC;
    return AppCard(
      key: ValueKey('site-card-${footLayout.zones[view.site].id}'),
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TempSiteIcon(
                  site: view.site,
                  state: view.missing
                      ? SiteIconState.missing
                      : view.alerting
                      ? SiteIconState.alerting
                      : SiteIconState.normal,
                ),
                const SizedBox(width: Dimens.tightGap),
                Expanded(child: Text(view.siteTh, style: AppText.bodyStrong)),
              ],
            ),
            const SizedBox(height: Dimens.tightGap),
            if (d == null)
              Text(
                '—',
                style: AppText.bigNumber.copyWith(color: AppColors.inkMuted),
              )
            else
              Semantics(
                label: '${formatDelta(d)}$nbspองศา',
                excludeSemantics: true,
                child: AnimatedNumber(
                  value: d,
                  format: (x) => '${formatDelta(x)}°',
                  style: AppText.bigNumber.copyWith(
                    color: view.alerting ? rest.text : null,
                  ),
                ),
              ),
            const Text('ต่างกันซ้าย–ขวา', style: AppText.secondary),
            const SizedBox(height: Dimens.tightGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (view.alerting) ...[
                  Icon(
                    LucideIcons.octagon_alert,
                    size: Dimens.smallCardIcon,
                    color: rest.icon,
                  ),
                  const SizedBox(width: Dimens.textGap),
                ],
                Expanded(
                  child: Text(
                    view.note,
                    style: AppText.labelStrong.copyWith(
                      color: view.alerting ? rest.text : null,
                    ),
                  ),
                ),
              ],
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
      sites: view.shownSites,
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
          TempChartLegend(sites: view.shownSites),
          const SizedBox(height: Dimens.buttonGap),
          Text(
            'แอปจะเตือนเมื่อเส้นขึ้นไปถึงแถบสีแดงติดกัน '
            '${t.consecutiveReadings}$nbspครั้ง',
            style: AppText.secondary,
          ),
        ],
      ),
    );
  }
}
