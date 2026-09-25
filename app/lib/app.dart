import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/models/app_config.dart';
import 'features/auth/login_screen.dart';
import 'features/bootstrap/splash_screen.dart';
import 'features/branding/brand.dart';
import 'features/home/home_screen.dart';

class RmPulseApp extends StatelessWidget {
  const RmPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return MaterialApp(
      title: 'RM Pulse',
      debugShowCheckedModeBanner: false,
      theme: app.ready ? _themeFrom(app.appConfig) : ThemeData.light(useMaterial3: true),
      home: !app.ready ? const SplashScreen() : const _Gate(),
    );
  }

  /// Builds the Material theme entirely from the JSON `themeConfig` + fonts.
  ThemeData _themeFrom(AppConfig cfg) {
    final t = cfg.theme;
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: Brand.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Brand.royalBlue,
        primary: Brand.royalBlue,
        secondary: t.accent,
        error: t.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Brand.royalBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: cfg.fonts.fontStyle,
        bodyColor: Brand.inkNavy,
        displayColor: Brand.inkNavy,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.royalBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.royalBlue,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: Brand.fieldBorder),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: Brand.royalBlueLight,
        secondarySelectedColor: Brand.royalBlueLight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Brand.fieldBorder)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.royalBlueLight, width: 1.6),
        ),
      ),
    );
  }
}

/// Decides between login and home based on auth state.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  late Future<bool> _loggedIn;

  @override
  void initState() {
    super.initState();
    _loggedIn = context.read<AppState>().auth.isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loggedIn,
      builder: (context, snap) {
        // Show the spinner only while the check is genuinely pending.
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // Done: if the check errored or returned false, fall through to login
        // (never spin forever on a storage error — the OnePlus hang).
        return (snap.data ?? false) ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
