import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clock.dart';
import '../routes.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/foot_check_card.dart';
import '../widgets/placeholder_body.dart';

/// Home skeleton (DESIGN-SPEC section 5). Layout slots only; live data,
/// status card and foot map arrive in S5.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageBody(
          children: [
            _Header(date: thaiLongDate(now)),
            const _FootButtons(),
            const PlaceholderBody(session: 'S5'),
            // Shown unconditionally until S8C adds "done today" logic.
            FootCheckCard(
              onTap: () => Navigator.pushNamed(context, Routes.footCheck),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: AppText.secondary),
              const Text('สวัสดี', style: AppText.screenTitle),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: Dimens.floatingShadow,
          ),
          child: IconButton(
            key: const ValueKey('settings-button'),
            icon: const Icon(LucideIcons.settings),
            tooltip: 'ตั้งค่า',
            onPressed: () => Navigator.pushNamed(context, Routes.settings),
          ),
        ),
      ],
    );
  }
}

class _FootButtons extends StatelessWidget {
  const _FootButtons();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _FootButton(key: ValueKey('foot-left'), label: 'เท้าซ้าย'),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _FootButton(key: ValueKey('foot-right'), label: 'เท้าขวา'),
        ),
      ],
    );
  }
}

/// Left/right foot button. Always "not connected" until BLE exists (S3A);
/// grey dot, never the connected green.
class _FootButton extends StatelessWidget {
  const _FootButton({super.key, required this.label});

  final String label;

  static const _radius = BorderRadius.all(Radius.circular(Dimens.radiusTip));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: _radius,
        onTap: () => Navigator.pushNamed(context, Routes.connection),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.footButtonHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.deviceDisconnected,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppText.bodyStrong),
                      const Text('ไม่ได้เชื่อมต่อ', style: AppText.small),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
