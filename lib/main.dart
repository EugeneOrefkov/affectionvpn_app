import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/messenger.dart';
import 'core/window/app_window.dart';
import 'screens/splash_screen.dart';
import 'services/linux_tray.dart';
import 'services/linux_vless_platform.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    VlessPlatform.instance = LinuxVlessPlatform();
    await initializeAppWindow();
  }
  runApp(const AffectionVpnApp());
}

class AffectionVpnApp extends StatefulWidget {
  const AffectionVpnApp({super.key});

  @override
  State<AffectionVpnApp> createState() => _AffectionVpnAppState();
}

class _AffectionVpnAppState extends State<AffectionVpnApp> {
  @override
  void initState() {
    super.initState();
    if (Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = context.read<AppState>();
        LinuxTray.instance.init(state);
      });
    }
  }

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
        builder: (context, child) => WindowFrame(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
