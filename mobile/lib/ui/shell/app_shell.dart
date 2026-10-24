import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/storage_providers.dart';
import '../screens/alerts_screen.dart';
import '../screens/foot_check_screen.dart';
import '../screens/home_screen.dart';
import '../screens/my_feet_screen.dart';
import 'bottom_bar.dart';

/// The four bottom-bar tabs (DESIGN-SPEC §4). The old Gait and Temperature
/// tabs are sub-tabs of My feet.
enum AppTab { today, myFeet, footCheck, alerts }

class SelectedTab extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.today;

  void select(AppTab tab) => state = tab;
}

final selectedTabProvider = NotifierProvider<SelectedTab, AppTab>(
  SelectedTab.new,
);

/// The sub-tabs of My feet (DESIGN-SPEC §8). Home's "ดูเพิ่ม" and the
/// pressure alerts open [pressure]; `TEMP_DELTA` opens [temperature].
enum MyFeetTab { pressure, temperature, gait }

class SelectedMyFeetTab extends Notifier<MyFeetTab> {
  @override
  MyFeetTab build() => MyFeetTab.pressure;

  void select(MyFeetTab tab) => state = tab;
}

final myFeetTabProvider = NotifierProvider<SelectedMyFeetTab, MyFeetTab>(
  SelectedMyFeetTab.new,
);

/// Opens My feet on [tab] from anywhere: back to the tab shell (closing
/// pushed screens such as an alert detail), then the tab and sub-tab.
void openMyFeet(BuildContext context, WidgetRef ref, MyFeetTab tab) {
  ref.read(myFeetTabProvider.notifier).select(tab);
  ref.read(selectedTabProvider.notifier).select(AppTab.myFeet);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Unread alerts, for the Alerts tab badge: 0 until the store has answered
/// (and when it is empty). Tests override it.
final unreadAlertCountProvider = Provider<int>(
  (ref) => ref.watch(unreadAlertsProvider).value ?? 0,
);

/// Whether the store has answered: the first count at start-up is not a
/// new alert, so the bell does not wiggle for it.
final unreadAlertsKnownProvider = Provider<bool>(
  (ref) => ref.watch(unreadAlertsProvider).hasValue,
);

const appTabs = [
  BottomBarItem(tab: AppTab.today, icon: LucideIcons.house, label: 'วันนี้'),
  BottomBarItem(
    tab: AppTab.myFeet,
    icon: LucideIcons.footprints,
    label: 'เท้าของฉัน',
  ),
  BottomBarItem(
    tab: AppTab.footCheck,
    icon: LucideIcons.camera,
    label: 'ตรวจเท้า',
  ),
  BottomBarItem(tab: AppTab.alerts, icon: LucideIcons.bell, label: 'แจ้งเตือน'),
];

/// Tab host. Tabs keep their state (IndexedStack); pushed screens
/// (Connection, Settings, …) cover the bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(selectedTabProvider);
    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [
          HomeScreen(),
          MyFeetScreen(),
          FootCheckScreen(),
          AlertsScreen(),
        ],
      ),
      bottomNavigationBar: BottomBar(
        items: appTabs,
        selected: tab,
        unreadAlerts: ref.watch(unreadAlertCountProvider),
        animateBadge: ref.watch(unreadAlertsKnownProvider),
        onSelect: ref.read(selectedTabProvider.notifier).select,
      ),
    );
  }
}
