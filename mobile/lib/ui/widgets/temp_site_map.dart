import 'package:flutter/material.dart';

import '../../ble/packets.dart';
import '../../config/foot_layout.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import 'foot_map.dart';

/// One foot with its two temperature sites (DESIGN-SPEC §7.3, "ตำแหน่งที่
/// พบ" for `TEMP_DELTA`). [warmSite] is the site that is warmer than the
/// same site on the other foot: Rest-your-feet fill and stroke plus a
/// 3 px ring at radius 23; every other site is white with a 2 px
/// `inkMuted` stroke. Still (no motion on the alert detail, §12.2). One
/// screen-reader image with [semanticLabel].
class TempSiteMap extends StatelessWidget {
  const TempSiteMap({
    super.key,
    required this.side,
    required this.semanticLabel,
    required this.width,
    required this.height,
    this.warmSite,
  });

  final FootSide side;
  final TempSite? warmSite;
  final String semanticLabel;
  final double width;
  final double height;

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
          painter: _TempSitePainter(side: side, warmSite: warmSite),
        ),
      ),
    );
  }
}

class _TempSitePainter extends CustomPainter {
  _TempSitePainter({required this.side, required this.warmSite});

  final FootSide side;
  final TempSite? warmSite;

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, offset) = fitFootViewBox(size);
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    paintFootOutline(canvas, side);
    for (final t in footLayout.tempSites) {
      final c = side == FootSide.left ? t.left : t.right;
      final warm = t.site == warmSite;
      canvas
        ..drawCircle(
          c,
          TempSiteColors.radius,
          Paint()
            ..color = warm ? TempSiteColors.warmFill : TempSiteColors.otherFill,
        )
        ..drawCircle(
          c,
          TempSiteColors.radius,
          Paint()
            ..color = warm
                ? TempSiteColors.warmStroke
                : TempSiteColors.otherStroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = TempSiteColors.strokeWidth,
        );
      if (warm) {
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
      old.side != side || old.warmSite != warmSite;
}

/// Legend "จุดที่อุ่นกว่า" / "จุดวัดอื่น". Hidden from screen readers: the
/// maps carry their own labels.
class TempSiteLegend extends StatelessWidget {
  const TempSiteLegend({super.key, required this.textStyle});

  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    Widget item(Color fill, Color stroke, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: FootDotColors.medium.legendRadius * 2,
          height: FootDotColors.medium.legendRadius * 2,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: stroke,
              width: FootDotColors.legendOutlineWidth,
            ),
          ),
        ),
        const SizedBox(width: Dimens.tightGap),
        Text(label, style: textStyle),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Dimens.cardGap,
        runSpacing: Dimens.tightGap,
        children: [
          item(
            TempSiteColors.warmFill,
            TempSiteColors.warmStroke,
            'จุดที่อุ่นกว่า',
          ),
          item(
            TempSiteColors.otherFill,
            TempSiteColors.otherStroke,
            'จุดวัดอื่น',
          ),
        ],
      ),
    );
  }
}
