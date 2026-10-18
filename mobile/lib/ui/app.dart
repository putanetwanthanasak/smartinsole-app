import 'package:flutter/material.dart';

import 'routes.dart';
import 'screens/connection_screen.dart';
import 'screens/foot_check_screen.dart';
import 'screens/settings_screen.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

class SmartInsoleApp extends StatelessWidget {
  const SmartInsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartInsole',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('th'),
      supportedLocales: const [Locale('th')],
      initialRoute: Routes.shell,
      routes: {
        Routes.shell: (_) => const AppShell(),
        Routes.connection: (_) => const ConnectionScreen(),
        Routes.settings: (_) => const SettingsScreen(),
        Routes.footCheck: (_) => const FootCheckScreen(),
      },
    );
  }
}
