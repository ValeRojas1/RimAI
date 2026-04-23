import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/screens/auth/register_screen.dart';
import 'package:rimai_app/adapters/input/screens/auth/login_screen.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';

/// Proveedor del enrutador principal de la aplicación, conectado al estado de Riverpod.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authStorage = ref.watch(authStorageProvider);

  return GoRouter(
    initialLocation: '/auth/login',
    redirect: (context, state) async {
      final token = await authStorage.getToken();
      final isAuthRoute = state.uri.toString().startsWith('/auth');

      // Si no hay token y no se está en una ruta de auth, redirigir a login
      if (token == null && !isAuthRoute) {
        return '/auth/login';
      }

      // Si hay token y el usuario intenta acceder al login/registro,
      // redirigir al panel correspondiente según su rol.
      if (token != null && isAuthRoute) {
        final role = await authStorage.getRole();
        if (role == 'terapeuta') {
          return '/terapeuta/dashboard';
        } else if (role == 'padre_tutor' || role == 'tutor') {
          return '/familia/dashboard';
        } else if (role == 'admin') {
          return '/admin/dashboard';
        }
        return '/home'; // fallback
      }

      return null; // Permitir navegación
    },
    routes: [
      GoRoute(
        path: '/auth',
        redirect: (_, __) => '/auth/login', // por defecto va a login
      ),
      GoRoute(
        path: '/auth/login',
        name: 'login',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/auth/register',
        name: 'register',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const RegisterScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      // --- Pantallas Mock para dashboards ---
      GoRoute(
        path: '/terapeuta/dashboard',
        builder: (context, state) => _buildMockDashboard('Terapeuta Dashboard'),
      ),
      GoRoute(
        path: '/familia/dashboard',
        builder: (context, state) => _buildMockDashboard('Familia Dashboard'),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => _buildMockDashboard('Admin Dashboard'),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => _buildMockDashboard('Home Screen'),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Ruta no encontrada: ${state.uri}'),
      ),
    ),
  );
});

Widget _buildMockDashboard(String title) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Text('$title — próximamente')),
  );
}
