import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/device_providers.dart';
import '../../device/mock_data_source.dart';
import '../routes.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/app_back_button.dart';
import '../widgets/placeholder_body.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only in a debug run started with --dart-define=MOCK=<preset>.
    final mock = ref.watch(mockInsolesProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: const Text('ตั้งค่า'),
      ),
      body: PageBody(
        children: [
          const PlaceholderBody(session: 'S8B'),
          // Researcher tool for the study (S4C); in release builds too.
          const _ResearcherGroup(),
          // Temporary developer entry (S3A); removed with the debug screen
          // in S8B.
          OutlinedButton(
            key: const ValueKey('ble-debug-button'),
            onPressed: () => Navigator.pushNamed(context, Routes.bleDebug),
            child: const Text('BLE debug (temporary)'),
          ),
          if (mock != null) _MockPresetButton(mock: mock),
        ],
      ),
    );
  }
}

/// Debug builds with the mock only: switches the mock preset live, so
/// every Home state can be shown on the emulator without relaunching.
class _MockPresetButton extends StatelessWidget {
  const _MockPresetButton({required this.mock});

  final MockInsoles mock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mock,
      builder: (context, _) => OutlinedButton(
        key: const ValueKey('mock-preset-button'),
        onPressed: () => _pick(context),
        child: Text('Mock preset (debug): ${mock.preset.name}'),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<MockPreset>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in MockPreset.values)
              ListTile(
                key: ValueKey('mock-preset-${p.name}'),
                title: Text(p.name),
                trailing: p == mock.preset
                    ? const Icon(LucideIcons.check)
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) mock.preset = picked;
  }
}

/// "สำหรับผู้วิจัย" group (DESIGN-SPEC §10.1): one row that opens only
/// after a 2-second long press, so a patient cannot open it by accident.
/// It opens the research capture flow directly; the Researcher screen
/// itself is S8B. TalkBack users trigger it with the long-press action
/// (double-tap and hold).
class _ResearcherGroup extends StatelessWidget {
  const _ResearcherGroup();

  /// How long the row must be held (§10.1). An input gate, not an
  /// animation.
  static const hold = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.pushNamed(context, Routes.capture);
    final palette = StatusColors.noData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'สำหรับผู้วิจัย',
          style: AppText.label.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Dimens.tightGap),
        Semantics(
          button: true,
          label: 'ส่วนผู้วิจัย',
          hint: 'กดค้าง 2 วินาทีเพื่อเปิด',
          onLongPress: open,
          excludeSemantics: true,
          child: RawGestureDetector(
            key: const ValueKey('researcher-row'),
            gestures: {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(duration: hold),
                    (r) => r.onLongPress = open,
                  ),
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Dimens.radiusCard),
                border: Border.all(color: AppColors.divider),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: Dimens.listRowHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.smallCardPadding,
                    vertical: Dimens.buttonGap,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: Dimens.listRowCircle,
                        height: Dimens.listRowCircle,
                        decoration: BoxDecoration(
                          color: palette.background,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.lock,
                          size: Dimens.listRowIcon,
                          color: palette.icon,
                        ),
                      ),
                      const SizedBox(width: Dimens.cardGap),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ส่วนผู้วิจัย', style: AppText.bodyStrong),
                            Text(
                              'กดค้าง 2 วินาทีเพื่อเปิด',
                              style: AppText.secondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
