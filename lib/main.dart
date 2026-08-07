import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/messenger.dart';
import 'screens/splash_screen.dart';
import 'services/linux_vless_platform.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setAsFrameless();
      await windowManager.setPreventClose(true);
      await windowManager.setMinimumSize(const Size(800, 500));
      await windowManager.setResizable(true);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setTitle('Affection VPN');
      await windowManager.show();
    });
    VlessPlatform.instance = LinuxVlessPlatform();
    _registerTrayShutdownBridge();
  }
  runApp(const AffectionVpnApp());
}

/// The native system-tray "Выход" item asks Dart to tear the tunnel down
/// before the process exits, so the xray core and the system proxy do not
/// linger after quit.
void _registerTrayShutdownBridge() {
  const channel = MethodChannel('dev.affection.affection_vpn/shutdown');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'quit') {
      await AppState.instance?.shutdown();
    }
  });
}

class AffectionVpnApp extends StatelessWidget {
  const AffectionVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Affection VPN',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: AppTheme.dark(),
        home: const SplashScreen(),
      ),
    );
  }
}
