import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'config.dart';
import 'screens/main_shell.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/your_name_screen.dart';
import 'services/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FieldLocatorApp());
}

class FieldLocatorApp extends StatefulWidget {
  const FieldLocatorApp({super.key});

  @override
  State<FieldLocatorApp> createState() => _FieldLocatorAppState();
}

class _FieldLocatorAppState extends State<FieldLocatorApp> {
  AppState? _state;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final results = await Future.wait([
        AppState.load(),
        Future<void>.delayed(const Duration(milliseconds: 700)), // let the splash show
      ]);
      final state = results.first as AppState;
      setState(() => _state = state);
      if (state.loggedIn) state.refreshAll();
      if (state.loggedIn) state.checkForUpdate();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SplashScreen(error: _error?.toString()),
      );
    }
    return AppScope(
      state: state,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Profile → Display → Large text.
        builder: (context, child) {
          if (!state.largeText) return child!;
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * 1.18)),
            child: child!,
          );
        },
        home: const RootGate(),
      ),
    );
  }
}

/// First screen: login, "your name", or the customer list.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.loggedIn) return const LoginScreen();
    if (app.userName.isEmpty) return const YourNameScreen();
    return const MainShell();
  }
}
