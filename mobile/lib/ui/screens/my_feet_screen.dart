import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion.dart';
import '../shell/app_shell.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/page_title.dart';
import '../widgets/placeholder_body.dart';
import '../widgets/segmented_tabs.dart';
import 'my_feet/my_feet_model.dart';
import 'my_feet/pressure_tab.dart';
import 'my_feet/my_feet_widgets.dart' show TwoColumns;
import 'my_feet/temperature_tab.dart';

/// Bottom-bar tab "เท้าของฉัน" (DESIGN-SPEC §8): title, the sub-tabs, and
/// the selected panel. Home's "ดูเพิ่ม" and the alert details pick the
/// sub-tab through [myFeetTabProvider]. Gait is built in S8A.
///
/// Motion (§12.2): the tab indicator slides; the old panel fades out
/// (`exit`) and the new one fades in (`enter`, 80 ms later). Reduce
/// motion: instant.
class MyFeetScreen extends ConsumerStatefulWidget {
  const MyFeetScreen({super.key});

  @override
  ConsumerState<MyFeetScreen> createState() => _MyFeetScreenState();
}

class _MyFeetScreenState extends ConsumerState<MyFeetScreen> {
  /// Times the bottom-bar tab was opened: the chart draws in again each
  /// time (the tab stays built in the shell's IndexedStack).
  int _entries = 0;

  static const _options = [
    SegmentOption(
      value: MyFeetTab.pressure,
      label: 'แรงกด',
      key: ValueKey('my-feet-tab-pressure'),
    ),
    SegmentOption(
      value: MyFeetTab.temperature,
      label: 'อุณหภูมิ',
      key: ValueKey('my-feet-tab-temperature'),
    ),
    SegmentOption(
      value: MyFeetTab.gait,
      label: 'การเดิน',
      key: ValueKey('my-feet-tab-gait'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedTabProvider, (prev, next) {
      if (next == AppTab.myFeet && prev != AppTab.myFeet) {
        setState(() => _entries++);
      }
    });
    final tab = ref.watch(myFeetTabProvider);
    final exit = Motion.duration(context, Motion.exitDuration);
    final delay = Motion.duration(context, Motion.panelEnterDelay);
    final enter = Motion.duration(context, Motion.enterDuration);
    final total = delay + enter;
    final inCurve = total == Duration.zero
        ? Motion.enter
        : Interval(
            delay.inMicroseconds / total.inMicroseconds,
            1,
            curve: Motion.enter,
          );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          key: const ValueKey('my-feet-scroll'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pageBottom,
          ),
          children: [
            const _Header(),
            const SizedBox(height: Dimens.sectionGap),
            SegmentedTabs<MyFeetTab>(
              options: _options,
              selected: tab,
              semanticLabel: 'เรื่องที่ดู',
              onSelect: ref.read(myFeetTabProvider.notifier).select,
            ),
            const SizedBox(height: Dimens.sectionGap),
            AnimatedSwitcher(
              duration: total,
              reverseDuration: exit,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: inCurve,
                  reverseCurve: Motion.exit.flipped,
                ),
                child: child,
              ),
              child: KeyedSubtree(
                key: ValueKey('my-feet-panel-${tab.name}'),
                child: switch (tab) {
                  MyFeetTab.pressure => const PressureTab(),
                  MyFeetTab.temperature => TemperatureTab(drawInKey: _entries),
                  MyFeetTab.gait => const PlaceholderBody(
                    key: ValueKey('my-feet-target-gait'),
                    session: 'S8A · tab: gait',
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "เท้าของฉัน" with "อัปเดตเมื่อสักครู่" right-aligned on the same line
/// ("ยังไม่มีข้อมูล" while no foot streams).
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final any = ref.watch(myFeetViewProvider.select((v) => v.anyUsable));
    final updated = Text(
      any ? 'อัปเดตเมื่อสักครู่' : 'ยังไม่มีข้อมูล',
      key: const ValueKey('my-feet-updated'),
      style: AppText.secondary,
      textAlign: TextAlign.end,
    );
    // Large text: the line goes under the title instead of squeezing it.
    if (MediaQuery.textScalerOf(context).scale(1) >
        TwoColumns.stackAboveScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const PageTitle('เท้าของฉัน'), updated],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Expanded(child: PageTitle('เท้าของฉัน')),
        const SizedBox(width: Dimens.tightGap),
        Flexible(child: updated),
      ],
    );
  }
}
