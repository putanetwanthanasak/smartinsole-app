import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../rules/alert_copy.dart' show sideTh;
import '../../../rules/pressure_level.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/details_expander.dart';
import '../../widgets/foot_map.dart';
import '../home/home_copy.dart' show mapLabel;
import '../home/home_model.dart' show FootMapView;
import 'my_feet_copy.dart';
import 'my_feet_model.dart';
import 'my_feet_widgets.dart';

/// My feet › "แรงกด" (DESIGN-SPEC §8.1): banner, both feet with the top
/// zones, and the numbers behind "ดูตัวเลขละเอียด". Each section selects
/// only what it shows from [myFeetViewProvider].
class PressureTab extends ConsumerWidget {
  const PressureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(
      myFeetViewProvider.select((v) => pressureBanner(v.pressure)),
    );
    final any = ref.watch(
      myFeetViewProvider.select(
        (v) => v.pressure.left.usable || v.pressure.right.usable,
      ),
    );
    return Column(
      key: const ValueKey('pressure-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFeetBanner(view: banner),
        const SizedBox(height: Dimens.sectionGap),
        const _MapCard(),
        // No data: no details expander (§8).
        if (any) ...[
          const SizedBox(height: Dimens.sectionGap),
          const _Details(),
        ],
      ],
    );
  }
}

class _MapCard extends ConsumerWidget {
  const _MapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (left, right, zones) = ref.watch(
      myFeetViewProvider.select(
        (v) => (v.pressure.left.map, v.pressure.right.map, _Zones(v.pressure)),
      ),
    );
    final any = left.hasData || right.hasData;
    return AppCard(
      key: const ValueKey('pressure-map-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('น้ำหนักที่เท้ารับอยู่ตอนนี้', style: AppText.cardTitle),
          const SizedBox(height: Dimens.cardGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabelledFoot(map: left),
              const SizedBox(width: Dimens.feetFootGap),
              _LabelledFoot(map: right),
            ],
          ),
          const SizedBox(height: Dimens.cardGap),
          const PressureLegend(textStyle: AppText.secondary),
          const SizedBox(height: Dimens.cardGap),
          if (any) ...[
            Text(
              'จุดที่รับน้ำหนักมากที่สุดตอนนี้',
              style: AppText.labelStrong.copyWith(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Dimens.tightGap),
            for (final z in zones.rows) _ZoneRowTile(row: z),
          ] else
            Text(
              'ยังไม่มีข้อมูล ต้องเชื่อมต่อแผ่นรองเท้าก่อน',
              key: const ValueKey('pressure-no-data'),
              style: AppText.labelStrong.copyWith(color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// The top-zone rows, compared by value for `select`.
class _Zones {
  _Zones(PressureTabView v) : rows = topZones(v);

  final List<ZoneRow> rows;

  @override
  bool operator ==(Object other) =>
      other is _Zones && listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hashAll(rows);
}

class _LabelledFoot extends StatelessWidget {
  const _LabelledFoot({required this.map});

  final FootMapView map;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FootMap(
          key: ValueKey('feet-map-${map.side.name}'),
          side: map.side,
          levels: map.levels,
          semanticLabel: mapLabel(map),
          width: Dimens.feetFootWidth,
          height: Dimens.feetFootHeight,
          dashOutlineWhenNoData: true,
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

/// One row of "จุดที่รับน้ำหนักมากที่สุดตอนนี้": dot (level radius × 0.8),
/// zone over side, level word ("มาก" in the Be-careful text colour with
/// `triangle-alert` 18).
class _ZoneRowTile extends StatelessWidget {
  const _ZoneRowTile({required this.row});

  final ZoneRow row;

  @override
  Widget build(BuildContext context) {
    final style = dotStyleOf(row.level);
    final d = style.radius * Dimens.zoneRowDotScale * 2;
    final high = row.level == PressureLevel.high;
    final levelStyle = AppText.labelStrong.copyWith(
      fontWeight: FontWeight.w700,
      color: high ? StatusColors.careful.text : AppColors.ink,
    );
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Dimens.detailRowPaddingV),
        decoration: topDivider,
        child: Row(
          children: [
            SizedBox(
              width: FootDotColors.high.radius * Dimens.zoneRowDotScale * 2,
              child: Center(
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    color: style.fill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.inkMuted,
                      width: FootDotColors.legendOutlineWidth,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Dimens.buttonGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.zoneTh, style: AppText.bodyStrong),
                  Text(row.sideText, style: AppText.secondary),
                ],
              ),
            ),
            const SizedBox(width: Dimens.tightGap),
            if (high) ...[
              Icon(
                LucideIcons.triangle_alert,
                size: Dimens.tagIcon,
                color: StatusColors.careful.icon,
              ),
              const SizedBox(width: Dimens.textGap),
            ],
            Text(row.level.th, style: levelStyle),
          ],
        ),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(myFeetViewProvider.select((v) => v.pressure));
    final t = ref.watch(thresholdsProvider);
    return DetailsExpander(
      key: const ValueKey('pressure-details'),
      leading: _KpaTable(left: v.left.kpa, right: v.right.kpa),
      rows: pressureDetailRows(v, t),
    );
  }
}

/// "แรงกดตอนนี้ (kPa)": zones down, "ซ้าย" / "ขวา" across, numbers
/// right-aligned in 64 px columns with tabular figures (§8.1).
class _KpaTable extends StatelessWidget {
  const _KpaTable({required this.left, required this.right});

  final List<int>? left;
  final List<int>? right;

  static const _column = 64.0;

  @override
  Widget build(BuildContext context) {
    const numbers = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    final value = AppText.labelStrong.merge(numbers);
    Widget row(String zone, String l, String r, {bool header = false}) {
      final style = header ? AppText.secondary : value;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: Dimens.textGap * 2),
        decoration: header ? null : topDivider,
        child: Row(
          children: [
            Expanded(
              child: Text(
                zone,
                style: header ? AppText.secondary : AppText.labelStrong,
              ),
            ),
            SizedBox(
              width: _column,
              child: Text(l, style: style, textAlign: TextAlign.end),
            ),
            SizedBox(
              width: _column,
              child: Text(r, style: style, textAlign: TextAlign.end),
            ),
          ],
        ),
      );
    }

    String at(List<int>? kpa, int c) => kpa == null ? '—' : '${kpa[c]}';
    return Container(
      key: const ValueKey('kpa-table'),
      padding: const EdgeInsets.only(bottom: Dimens.tightGap),
      decoration: topDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Dimens.detailRowPaddingV),
          Text('แรงกดตอนนี้ (kPa)', style: AppText.secondary),
          row('จุด', 'ซ้าย', 'ขวา', header: true),
          for (var c = 0; c < footLayout.zones.length; c++)
            row(footLayout.zones[c].nameTh, at(left, c), at(right, c)),
        ],
      ),
    );
  }
}
