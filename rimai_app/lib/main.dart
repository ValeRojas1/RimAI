import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Se remueve allowRuntimeFetching = false para que la app pueda descargar
  // la fuente PlusJakartaSans por internet.
  runApp(
    const ProviderScope(
      child: RimAIApp(),
    ),
  );
}

class RimAIApp extends ConsumerWidget {
  const RimAIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'RimAI — Plataforma Terapéutica',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: PMV2Theme.theme,
    );
  }
}
