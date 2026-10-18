import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/alerts_screen.dart';
import '../screens/gait_screen.dart';
import '../screens/home_screen.dart';
import '../screens/temperature_screen.dart';
import 'bottom_bar.dart';

enum AppTab { home, gait, temperature, alerts }

class SelectedTab extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void select(AppTab tab) => state = tab;
}

final selectedTabProvider = NotifierProvider<SelectedTab, AppTab>(
  SelectedTab.new,
);

/// The four bottom-bar tabs (DESIGN-SPEC section 4).
const appTabs = [
  BottomBarItem(tab: AppTab.home, icon: LucideIcons.house, label: 'หน้าหลัก'),
  BottomBarItem(
    tab: AppTab.gait,
    icon: LucideIcons.footprints,
    label: 'การเดิน',
  ),
  BottomBarItem(
    tab: AppTab.temperature,
    icon: LucideIcons.thermometer,
    label: 'อุณหภูมิ',
  ),
  BottomBarItem(tab: AppTab.alerts, icon: LucideIcons.bell, label: 'แจ้งเตือน'),
];

/// Tab host. Tabs keep their state (IndexedStack); pushed screens
/// (Connection, Settings, Foot check) cover the bar.
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
          GaitScreen(),
          TemperatureScreen(),
          AlertsScreen(),
        ],
      ),
      bottomNavigationBar: BottomBar(
        items: appTabs,
        selected: tab,
        // Wired to the alert store in S6B.
        alertCount: 0,
        onSelect: ref.read(selectedTabProvider.notifier).select,
      ),
    );
  }
}
