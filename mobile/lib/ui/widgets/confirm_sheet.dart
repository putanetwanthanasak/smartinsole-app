import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import 'buttons.dart';
import 'info_box.dart';
import 'numbered_steps.dart';

/// Opens [sheet] as the confirmation bottom sheet of DESIGN-SPEC §5 (the
/// TARE pattern): scrim `camBg` at 60 %, white sheet with top corners 24.
/// Every S8B confirmation uses it (§14).
Future<T?> showConfirmSheet<T>(BuildContext context, Widget sheet) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      barrierColor: CameraColors.background.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Dimens.radiusViewfinder),
        ),
      ),
      // Material's sheet ignores reduce motion; it jumps in and out here
      // (§12.3, rule 16).
      sheetAnimationStyle: Motion.reduced(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => sheet,
    );

/// The sheet's body (§5): padding 12 24 32, gap 16; a 40×4 `divider`
/// handle; title 24/700; text 16 `inkMuted`; numbered steps (12 apart); a
/// warning box; [child] for anything else (a text field, progress); two
/// buttons side by side, 12 apart: secondary (cancel) left, primary
/// (confirm) right. A null [confirmLabel] leaves one full-width button
/// ([cancelLabel], e.g. "ปิด" once something is done); no labels at all
/// leave no buttons (an action in progress).
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    this.text,
    this.steps = const [],
    this.warning,
    this.child,
    this.cancelLabel,
    this.confirmLabel,
    this.onCancel,
    this.onConfirm,
  });

  final String title;
  final String? text;
  final List<String> steps;
  final String? warning;
  final Widget? child;
  final String? cancelLabel;
  final String? confirmLabel;

  /// Defaults to closing the sheet with no result.
  final VoidCallback? onCancel;

  /// Null disables the confirm button.
  final VoidCallback? onConfirm;

  static const _handleWidth = 40.0;
  static const _handleHeight = 4.0;
  static const _paddingTop = 12.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final cancel = onCancel ?? () => Navigator.pop(context);
    final parts = <Widget>[
      Semantics(header: true, child: Text(title, style: AppText.sheetTitle)),
      if (text != null) Text(text!, style: AppText.secondary),
      if (steps.isNotEmpty)
        NumberedSteps(steps: steps, stepGap: Dimens.buttonGap),
      if (warning != null)
        WarningBox(text: warning!, radius: Dimens.radiusInner),
      ?child,
      if (confirmLabel == null && cancelLabel != null)
        SecondaryButton(
          key: const ValueKey('sheet-cancel'),
          label: cancelLabel!,
          onPressed: cancel,
        )
      else if (confirmLabel != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SecondaryButton(
                key: const ValueKey('sheet-cancel'),
                label: cancelLabel ?? 'ยกเลิก',
                onPressed: cancel,
              ),
            ),
            const SizedBox(width: Dimens.buttonGap),
            Expanded(
              child: PrimaryButton(
                key: const ValueKey('sheet-confirm'),
                label: confirmLabel!,
                onPressed: onConfirm,
              ),
            ),
          ],
        ),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Dimens.pagePadding,
        _paddingTop,
        Dimens.pagePadding,
        Dimens.pageBottomPushed + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: _handleWidth,
              height: _handleHeight,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(_handleHeight / 2),
              ),
            ),
          ),
          for (final p in parts) ...[const SizedBox(height: Dimens.cardGap), p],
        ],
      ),
    );
  }
}
