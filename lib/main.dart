import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/api/api_client.dart';
import 'package:hrm_app/app/router.dart';
import 'package:hrm_app/auth/auth_service.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/auth/token_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await tokenService.load();

  final authStore = AuthStore();

  // When a token refresh fails, log out; the router then shows /login.
  onSessionExpired = authStore.logout;

  // Restore the session if saved tokens are still valid (Bootstrap in main.tsx).
  if (tokenService.getAccess() != null) {
    try {
      authStore.setUser(await authService.me());
    } catch (_) {
      await tokenService.clear();
    }
  }

  runApp(
    ChangeNotifierProvider.value(
      value: authStore,
      child: App(authStore: authStore),
    ),
  );
}

class App extends StatefulWidget {
  const App({super.key, required this.authStore});

  final AuthStore authStore;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter(widget.authStore);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BTrillions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFFF8F9FC),
      ),
      routerConfig: _router,
    );
  }
}