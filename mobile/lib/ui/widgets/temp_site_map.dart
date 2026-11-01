import 'package:flutter/material.dart';

import '../../ble/packets.dart';
import '../../config/foot_layout.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import 'foot_map.dart';

/// How one temperature site is drawn (DESIGN-SPEC §7.3, §8.2).
enum TempSiteMark {
  /// White with a 2 px `inkMuted` stroke: "จุดวัดอื่น" on the alert detail,
  /// "ใกล้เคียงกัน" on the Temperature tab.
  plain,

  /// Warmer than the same site on the other foot: Rest-your-feet fill and
  /// stroke.
  warm,

  /// [warm] plus a 3 px Rest ring: the site the alert names (alert
  /// detail), or a site where `TEMP_DELTA` holds now (Temperature tab).
  warmRinged,

  /// No two-foot reading to compare (rules 4 and 5): white with a dashed
  /// `inkSubtle` stroke, the No-data dot style; never "close".
  unreadable,
}

/// One foot with its 8 temperature sites (site i = zone i,
/// `shared/sensor_layout.json`), one [TempSiteMark] per site. Used by the
/// `TEMP_DELTA` alert detail ("ตำแหน่งที่พบ", §7.3) and the Temperature
/// tab's map card (§8.2). [dashedOutline]: a foot with no data on My feet.
/// Still (no motion). One screen-reader image with [semanticLabel].
class TempSiteMap extends StatelessWidget {
  const TempSiteMap({
    super.key,
    required this.side,
    required this.marks,
    required this.semanticLabel,
    required this.width,
    required this.height,
    this.dashedOutline = false,
  });

  final FootSide side;

  /// Indexed by zone; a missing entry is [TempSiteMark.plain].
  final List<TempSiteMark> marks;
  final String semanticLabel;
  final double width;
  final double height;
  final bool dashedOutline;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _TempSitePainter(
            side: side,
            marks: marks,
            dashedOutline: dashedOutline,
          ),
        ),
      ),
    );
  }
}

class _TempSitePainter extends CustomPainter {
  _TempSitePainter({
    required this.side,
    required this.marks,
    required this.dashedOutline,
  });

  final FootSide side;
  final List<TempSiteMark> marks;
  final bool dashedOutline;

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, offset) = fitFootViewBox(size);
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    paintFootOutline(canvas, side, dashed: dashedOutline);
    for (var i = 0; i < footLayout.zones.length; i++) {
      final c = footLayout.zones[i].position(side);
      final mark = i < marks.length ? marks[i] : TempSiteMark.plain;
      final warm = mark == TempSiteMark.warm || mark == TempSiteMark.warmRinged;
      final stroke = Paint()
        ..color = switch (mark) {
          TempSiteMark.plain => TempSiteColors.otherStroke,
          TempSiteMark.unreadable => TempSiteColors.unreadableStroke,
          _ => TempSiteColors.warmStroke,
        }
        ..style = PaintingStyle.stroke
        ..strokeWidth = TempSiteColors.strokeWidth;
      canvas.drawCircle(
        c,
        TempSiteColors.radius,
        Paint()
          ..color = warm ? TempSiteColors.warmFill : TempSiteColors.otherFill,
      );
      if (mark == TempSiteMark.unreadable) {
        canvas.drawPath(
          dashedPath(
            Path()..addOval(
              Rect.fromCircle(center: c, radius: TempSiteColors.radius),
            ),
            noDataDotDash,
          ),
          stroke,
        );
      } else {
        canvas.drawCircle(c, TempSiteColors.radius, stroke);
      }
      if (mark == TempSiteMark.warmRinged) {
        canvas.drawCircle(
          c,
          TempSiteColors.ringRadius,
          Paint()
            ..color = TempSiteColors.warmStroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = TempSiteColors.ringWidth,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TempSitePainter old) =>
      old.side != side ||
      old.dashedOutline != dashedOutline ||
      !_sameMarks(old.marks, marks);
}

bool _sameMarks(List<TempSiteMark> a, List<TempSiteMark> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A legend dot for [mark] (legend size, `FootDotColors.medium`'s legend
/// radius). Also the dot of a Temperature top-3 row.
class TempSiteDot extends StatelessWidget {
  const TempSiteDot({super.key, required this.mark, this.radius});

  final TempSiteMark mark;

  /// Logical pixels; the legend radius by default.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? FootDotColors.medium.legendRadius;
    final warm = mark == TempSiteMark.warm || mark == TempSiteMark.warmRinged;
    return SizedBox(
      width: r * 2,
      height: r * 2,
      child: CustomPaint(
        painter: _DotPainter(mark: mark, warm: warm),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({required this.mark, required this.warm});

  final TempSiteMark mark;
  final bool warm;

  @override
  void paint(Canvas canvas, Size size) {
    const w = FootDotColors.legendOutlineWidth;
    final r = size.shortestSide / 2 - w / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = warm ? TempSiteColors.warmFill : TempSiteColors.otherFill,
    );
    final stroke = Paint()
      ..color = switch (mark) {
        TempSiteMark.plain => TempSiteColors.otherStroke,
        TempSiteMark.unreadable => TempSiteColors.unreadableStroke,
        _ => TempSiteColors.warmStroke,
      }
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    if (mark == TempSiteMark.unreadable) {
      canvas.drawPath(
        dashedPath(
          Path()..addOval(Rect.fromCircle(center: c, radius: r)),
          TempSiteColors.legendDash,
        ),
        stroke,
      );
    } else {
      canvas.drawCircle(c, r, stroke);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.mark != mark;
}

/// A temperature-site legend: [items] are each mark with its words.
/// Alert detail: "จุดที่อุ่นกว่า" / "จุดวัดอื่น"; Temperature tab:
/// "จุดที่อุ่นกว่า" / "ใกล้เคียงกัน" / "ยังวัดไม่ได้". Hidden from screen
/// readers: the maps carry their own labels.
class TempSiteLegend extends StatelessWidget {
  const TempSiteLegend({
    super.key,
    required this.textStyle,
    this.items = const [
      (TempSiteMark.warm, 'จุดที่อุ่นกว่า'),
      (TempSiteMark.plain, 'จุดวัดอื่น'),
    ],
  });

  final TextStyle textStyle;
  final List<(TempSiteMark, String)> items;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Dimens.cardGap,
        runSpacing: Dimens.tightGap,
        children: [
          for (final (mark, label) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TempSiteDot(mark: mark),
                const SizedBox(width: Dimens.tightGap),
                Text(label, style: textStyle),
              ],
            ),
        ],
      ),
    );
  }
}
