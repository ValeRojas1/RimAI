import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';

void main() {
  runApp(
    const ProviderScope(
      child: RimAIApp(),
    ),
  );
}

class RimAIApp extends StatelessWidget {
  const RimAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RimAI — Plataforma Terapéutica',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB8D6B2),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.light().textTheme,
        ),
        scaffoldBackgroundColor: const Color(0xFFFDFBF8),
      ),
    );
  }
}
