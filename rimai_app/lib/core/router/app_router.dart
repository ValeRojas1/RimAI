import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/screens/auth/register_screen.dart';
import 'package:rimai_app/adapters/input/screens/auth/login_screen.dart';
import 'package:rimai_app/adapters/input/screens/auth/auth_shell_screen.dart';
import 'package:rimai_app/adapters/input/screens/profile/therapeutic_profile_screen.dart';
import 'package:rimai_app/adapters/input/screens/ia/ia_assistant_screen.dart';
import 'package:rimai_app/adapters/input/screens/session/active_session_screen.dart';
import 'package:rimai_app/adapters/input/screens/session/session_summary_screen.dart';
import 'package:rimai_app/adapters/input/screens/progress/progress_screen.dart';
import 'package:rimai_app/adapters/input/screens/validation/clinical_validation_screen.dart';
import 'package:rimai_app/adapters/input/screens/dashboard/dashboard_screen.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';

/// Proveedor del enrutador principal de la aplicación, conectado al estado de Riverpod.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authStorage = ref.watch(authStorageProvider);

  return GoRouter(
    initialLocation: '/auth/login',
    redirect: (context, state) async {
      final token = await authStorage.getToken();
      final isAuthRoute = state.uri.toString().startsWith('/auth');

      // Sin token y fuera de auth → login
      if (token == null && !isAuthRoute) return '/auth/login';

      // Con token y en auth → redirigir al dashboard según rol
      if (token != null && isAuthRoute) {
        final role = await authStorage.getRole();
        if (role == 'terapeuta') return '/terapeuta/dashboard';
        if (role == 'padre_tutor' || role == 'tutor') return '/familia/dashboard';
        if (role == 'admin') return '/admin/dashboard';
        return '/terapeuta/dashboard'; // fallback
      }

      return null;
    },
    routes: [
      // ── Auth ───────────────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => AuthShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/auth',
            redirect: (_, __) => '/auth/login',
          ),
          GoRoute(
            path: '/auth/login',
            name: 'login',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const LoginScreen(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/auth/register',
            name: 'register',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const RegisterScreen(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
        ],
      ),

      // ── Terapeuta ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/terapeuta/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/terapeuta/perfil/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return TherapeuticProfileScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/ia',
        builder: (context, state) => const IAAssistantScreen(),
      ),
      GoRoute(
        path: '/terapeuta/sesion',
        builder: (context, state) => const ActiveSessionScreen(sesionId: '1'),
      ),
      GoRoute(
        path: '/terapeuta/sesion/:sesionId',
        builder: (context, state) {
          final sesionId = state.pathParameters['sesionId'] ?? '1';
          return ActiveSessionScreen(sesionId: sesionId);
        },
      ),
      GoRoute(
        path: '/terapeuta/sesion/resumen',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SessionSummaryScreen(
            totalAciertos: extra['aciertos'] as int? ?? 0,
            totalIntentos: extra['intentos'] as int? ?? 0,
            segundosTranscurridos: extra['segundos'] as int? ?? 0,
            nivelAyuda: extra['nivelAyuda'] as String? ?? 'Ninguna',
            ninoNombre: extra['ninoNombre'] as String? ?? 'Paciente',
          );
        },
      ),
      GoRoute(
        path: '/terapeuta/progreso',
        builder: (context, state) => const ProgressScreen(ninoId: '1'),
      ),
      GoRoute(
        path: '/terapeuta/progreso/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return ProgressScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/validacion/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return ClinicalValidationScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/calendario',
        builder: (context, state) => const _PlaceholderScreen(title: 'Calendario'),
      ),

      // ── Familia / Admin ────────────────────────────────────────────────────
      GoRoute(
        path: '/familia/dashboard',
        builder: (context, state) => const _PlaceholderScreen(title: 'Panel Familiar'),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const _PlaceholderScreen(title: 'Panel Administrador'),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const _PlaceholderScreen(title: 'Inicio'),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Ruta no encontrada: ${state.uri}')),
    ),
  );
});

/// Pantalla temporal para rutas no implementadas aún.
class _PlaceholderScreen extends ConsumerWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F2),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref.read(authStorageProvider).clearSession();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 64, color: Color(0xFF58423B)),
            const SizedBox(height: 16),
            Text('$title — próximamente', style: const TextStyle(color: Color(0xFF58423B))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/terapeuta/dashboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8D6B2),
                foregroundColor: const Color(0xFF1E1B16),
              ),
              child: const Text('Ir al Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
