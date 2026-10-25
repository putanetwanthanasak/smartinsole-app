import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../storage/storage_providers.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/summary_banner.dart';
import 'my_feet_copy.dart';

/// The banner of a My feet tab (§8.1, §8.2) from its [BannerView].
///
/// "ดูสิ่งที่ควรทำ" opens the newest stored alert of the banner's code
/// (the list's visibility rule). It is left out until that row exists,
/// e.g. for the moment while the engine is still writing it.
class MyFeetBanner extends ConsumerWidget {
  const MyFeetBanner({super.key, required this.view});

  final BannerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = view.linkCode;
    int? alertId;
    if (code != null) {
      final alerts = ref.watch(visibleAlertsProvider).value ?? const [];
      for (final a in alerts) {
        if (a.kind.code == code) {
          alertId = a.id;
          break;
        }
      }
    }
    return SummaryBanner(
      key: const ValueKey('my-feet-banner'),
      level: view.level,
      title: view.title,
      line: view.line,
      linkLabel: alertId == null ? null : 'ดูสิ่งที่ควรทำ',
      linkKey: const ValueKey('banner-link'),
      onLink: alertId == null
          ? null
          : () => Navigator.pushNamed(
              context,
              Routes.alertDetail,
              arguments: alertId,
            ),
      action: view.connect
          ? PrimaryButton(
              key: const ValueKey('banner-connect'),
              label: 'เชื่อมต่อแผ่นรองเท้า',
              icon: LucideIcons.bluetooth,
              onPressed: () => Navigator.pushNamed(context, Routes.connection),
            )
          : null,
    );
  }
}

/// Two cards side by side, stacked when the text is so large that a 36 px
/// number would not fit half the width (as Home's small cards, §13).
class TwoColumns extends StatelessWidget {
  const TwoColumns({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  /// Above this text scale the two cards stack (Home's value).
  static const stackAboveScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale > stackAboveScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: Dimens.gridGap),
          right,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: Dimens.gridGap),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// A divider line on top of a row (zone list, kPa table).
const topDivider = BoxDecoration(
  border: Border(top: BorderSide(color: AppColors.divider)),
);
