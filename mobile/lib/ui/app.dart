import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_text_scaler.dart';
import '../settings/settings_providers.dart';

import '../storage/storage_host.dart';

import 'routes.dart';
import 'screens/alert_detail_screen.dart';
import 'screens/capture/capture_home_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/debug_ble_screen.dart';
import 'screens/foot_check_found_screen.dart';
import 'screens/settings_screen.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

class SmartInsoleApp extends ConsumerWidget {
  const SmartInsoleApp({super.key, this.initialRoute = Routes.shell});

  /// Overridable so tests can open a pushed screen directly.
  final String initialRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factor = ref.watch(settingsProvider.select((s) => s.textSize.factor));
    return StorageHost(
      child: MaterialApp(
        title: 'SmartInsole',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('th', 'TH'),
        supportedLocales: const [Locale('th', 'TH')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Settings › "ขนาดตัวอักษร" multiplies the phone's own scale.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: AppTextScaler.combine(mq.textScaler, factor),
            ),
            child: child!,
          );
        },
        initialRoute: initialRoute,
        routes: {
          Routes.shell: (_) => const AppShell(),
          Routes.connection: (_) => const ConnectionScreen(),
          Routes.settings: (_) => const SettingsScreen(),
          Routes.alertDetail: (context) => AlertDetailScreen(
            alertId: ModalRoute.of(context)!.settings.arguments! as int,
          ),
          Routes.footCheckFound: (context) => FootCheckFoundScreen(
            footCheckId: ModalRoute.of(context)!.settings.arguments as int?,
          ),
          Routes.bleDebug: (_) => const DebugBleScreen(),
          Routes.capture: (_) => const CaptureHomeScreen(),
        },
      ),
    );
  }
}
