import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../storage/storage_host.dart';

import 'routes.dart';
import 'screens/capture/capture_home_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/debug_ble_screen.dart';
import 'screens/settings_screen.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

class SmartInsoleApp extends StatelessWidget {
  const SmartInsoleApp({super.key, this.initialRoute = Routes.shell});

  /// Overridable so tests can open a pushed screen directly.
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return StorageHost(
      child: MaterialApp(
        title: 'SmartInsole',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('th', 'TH'),
        supportedLocales: const [Locale('th', 'TH')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        initialRoute: initialRoute,
        routes: {
          Routes.shell: (_) => const AppShell(),
          Routes.connection: (_) => const ConnectionScreen(),
          Routes.settings: (_) => const SettingsScreen(),
          Routes.bleDebug: (_) => const DebugBleScreen(),
          Routes.capture: (_) => const CaptureHomeScreen(),
        },
      ),
    );
  }
}
