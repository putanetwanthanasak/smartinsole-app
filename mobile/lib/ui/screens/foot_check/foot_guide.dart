import 'package:flutter/material.dart';

import '../../../ble/packets.dart';
import '../../../footcheck/foot_views.dart';
import '../../../storage/models.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../widgets/foot_map.dart';

/// Which outline the guide draws: the foot as it looks in the preview
/// (decision 1). A top view seen by an unmirrored camera, or a sole seen
/// in the mirrored front preview, looks like the foot's own top-view
/// outline (big toe on the inner side); a sole seen by an unmirrored back
/// camera, or a top view in a mirrored preview, looks like the other one.
FootSide guideOutlineOf(FootView view, {required bool previewMirrored}) {
  final sameAsTop = view.isSole == previewMirrored;
  final left = view.isLeft == sameAsTop;
  return left ? FootSide.left : FootSide.right;
}

/// Dashed foot guide (DESIGN-SPEC §11.2): 140×312, `camGuide`, 2.5 px,
/// dash 7 6.
class FootGuide extends StatelessWidget {
  const FootGuide({super.key, required this.outline});

  final FootSide outline;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(Dimens.guideWidth, Dimens.guideHeight),
    painter: _GuidePainter(outline),
  );
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.outline);

  final FootSide outline;

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, offset) = fitFootViewBox(size);
    canvas
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    canvas.drawPath(
      dashedPath(footOutlines[outline]!, [
        for (final d in Dimens.guideDash) d / scale,
      ]),
      Paint()
        ..color = CameraColors.guide
        ..style = PaintingStyle.stroke
        ..strokeWidth = Dimens.guideStroke / scale
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.outline != outline;
}
