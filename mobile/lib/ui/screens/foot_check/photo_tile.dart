import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../footcheck/footcheck_providers.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/foot_map.dart';

/// A stored foot photo, cropped to fill its box. [cacheWidth] decodes a
/// small copy for thumbnails. Photos come only from the app-private
/// foot-photo folder (rule 15).
class FootPhoto extends ConsumerWidget {
  const FootPhoto({
    super.key,
    required this.path,
    this.cacheWidth,
    this.fit = BoxFit.cover,
  });

  /// Relative to the foot-photo folder.
  final String path;
  final int? cacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(footPhotoDirResolvedProvider).value;
    if (dir == null) {
      return const ColoredBox(color: CameraColors.viewfinder);
    }
    return Image.file(
      File(p.join(dir.path, path)),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) =>
          const ColoredBox(color: CameraColors.viewfinder),
    );
  }
}

/// A frame with no photo in it: a dashed `inkSubtle` outline on white and
/// a centred 16 `inkMuted` line ("ยังไม่มีรูปก่อนหน้า", "ไม่ได้ถ่าย").
class EmptyPhotoFrame extends StatelessWidget {
  const EmptyPhotoFrame({
    super.key,
    required this.text,
    this.radius = Dimens.radiusCard,
  });

  final String text;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedFrame(radius),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.tightGap),
        child: Text(
          text,
          style: AppText.secondary,
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class _DashedFrame extends CustomPainter {
  _DashedFrame(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(Dimens.answerBorder / 2);
    canvas
      ..drawRRect(rect, Paint()..color = AppColors.surface)
      ..drawPath(
        dashedPath(Path()..addRRect(rect), Dimens.emptyFrameDash),
        Paint()
          ..color = AppColors.inkSubtle
          ..style = PaintingStyle.stroke
          ..strokeWidth = Dimens.answerBorder,
      );
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.radius != radius;
}
