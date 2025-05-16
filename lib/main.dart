import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'src/providers/providers.dart';
import 'src/screens/job_edit_screen.dart';
import 'src/screens/job_list_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/settings_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final isLoggedIn = ref.watch(authStateProvider);

    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final isLoggedIn = ref.read(authStateProvider);
        final isLoginRoute = state.matchedLocation == '/login';

        if (!isLoggedIn && !isLoginRoute) return '/login';
        if (isLoggedIn && isLoginRoute) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(path: '/', builder: (context, state) => const JobListScreen()),
        GoRoute(
          path: '/job',
          builder: (context, state) => const JobEditScreen(),
        ),
        GoRoute(
          path: '/job/:id',
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return JobEditScreen(jobId: id);
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: '3D Print Queue',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
