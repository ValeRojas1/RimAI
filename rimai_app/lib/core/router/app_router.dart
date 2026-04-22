import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rimai_app/adapters/input/screens/auth/register_screen.dart';

/// Router principal de la aplicación usando GoRouter.
final GoRouter appRouter = GoRouter(
  initialLocation: '/register',
  routes: [
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Login Screen — próximamente')),
      ),
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Home Screen — próximamente')),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Text('Ruta no encontrada: ${state.uri}'),
    ),
  ),
);
