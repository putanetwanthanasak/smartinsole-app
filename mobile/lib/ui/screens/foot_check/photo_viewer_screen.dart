import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../clock.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import 'foot_check_copy.dart';
import 'photo_tile.dart';

class PhotoViewerArgs {
  const PhotoViewerArgs({
    required this.path,
    required this.title,
    required this.atMs,
  });

  final String path;
  final String title;
  final int atMs;
}

/// One foot photo full screen (photo history; draft, §14): camera
/// colours, pinch to zoom, "ปิด" at the top left. View-only.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.args});

  final PhotoViewerArgs args;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.fromMillisecondsSinceEpoch(args.atMs);
    final white = AppText.bodyStrong.copyWith(color: AppColors.surface);
    return Scaffold(
      backgroundColor: CameraColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.pagePadding,
                Dimens.tightGap,
                Dimens.pagePadding,
                0,
              ),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: FootCheckCopy.close,
                    excludeSemantics: true,
                    onTap: () => Navigator.pop(context),
                    child: InkWell(
                      key: const ValueKey('viewer-close'),
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(Dimens.radiusInner),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: Dimens.minTouchTarget,
                          minWidth: Dimens.minTouchTarget,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.x,
                              size: Dimens.iconButtonIcon,
                              color: AppColors.surface,
                            ),
                            const SizedBox(width: Dimens.textGap),
                            Text(FootCheckCopy.close, style: white),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Dimens.buttonGap),
                  Expanded(
                    child: Text(
                      '${args.title} · ${thaiWeekdayDayMonth(at)} ${hhmm(at)}',
                      textAlign: TextAlign.end,
                      style: AppText.secondary.copyWith(
                        color: CameraColors.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Semantics(
                image: true,
                label: '${FootCheckCopy.photo} ${args.title}',
                child: InteractiveViewer(
                  maxScale: _maxZoom,
                  child: SizedBox.expand(
                    child: FootPhoto(path: args.path, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _maxZoom = 5.0;
}
