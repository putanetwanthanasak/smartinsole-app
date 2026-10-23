import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Unread alerts, for the Alerts tab badge. Always 0 until the alert store
/// exists (S6A/S6B); tests override it.
final unreadAlertCountProvider = Provider<int>((ref) => 0);

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
        onSelect: ref.read(selectedTabProvider.notifier).select,
      ),
    );
  }
}
