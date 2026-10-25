import 'package:flutter/material.dart';

import '../../ble/packets.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import 'foot_map.dart';

/// One foot at 60×134 with the centre-of-pressure path of its latest step
/// (DESIGN-SPEC §8.3): the foot outline, the path in `primary`, 7 view-box
/// units wide. With no path (no step yet) only the outline is drawn.
class CopFoot extends StatelessWidget {
  const CopFoot({super.key, required this.side, required this.path});

  final FootSide side;

  /// View-box points, heel strike to toe-off; null or empty: none.
  final List<Offset>? path;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Dimens.copFootWidth,
      height: Dimens.copFootHeight,
      child: CustomPaint(
        painter: _CopPainter(side: side, path: path),
      ),
    );
  }
}

class _CopPainter extends CustomPainter {
  _CopPainter({required this.side, required this.path});

  final FootSide side;
  final List<Offset>? path;

  /// Path stroke, view-box units (§8.3).
  static const _width = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, offset) = fitFootViewBox(size);
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    paintFootOutline(canvas, side);
    final points = path;
    if (points != null && points.isNotEmpty) {
      final stroke = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (points.length == 1) {
        canvas.drawCircle(
          points.first,
          _width / 2,
          Paint()..color = AppColors.primary,
        );
      } else {
        canvas.drawPath(Path()..addPolygon(points, false), stroke);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CopPainter old) =>
      old.side != side || !identical(old.path, path);
}
