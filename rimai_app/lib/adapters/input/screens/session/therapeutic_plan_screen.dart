import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class TherapeuticPlanScreen extends ConsumerWidget {
  final String ninoId;
  const TherapeuticPlanScreen({super.key, required this.ninoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planActivoProvider(ninoId));

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: const RimAITopBar(
        title: 'Plan terapeutico',
        leadingIcon: Icons.assignment_outlined,
        iconColor: _kPrimary,
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 2) context.go('/terapeuta/ia/$ninoId');
          if (index == 3) context.go('/terapeuta/progreso/$ninoId');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Sesion'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'IA'),
          BottomNavItem(icon: Icons.insights, label: 'Progreso'),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 96 + MediaQuery.of(context).padding.top,
          left: 24,
          right: 24,
          bottom: 120,
        ),
        child: planAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: _kPrimary)),
          error: (err, _) => BentoCard(
            backgroundColor: _kSurface,
            child: Text('No se pudo cargar el plan: $err',
                style: const TextStyle(color: _kSubtext)),
          ),
          data: (plan) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.ninoNombre,
                  style: const TextStyle(
                      color: _kSubtext, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                plan.nombre,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: _kText),
              ),
              const SizedBox(height: 8),
              Text(
                'Nivel actual: ${plan.nivelDificultadActual}',
                style: const TextStyle(color: _kSubtext),
              ),
              const SizedBox(height: 28),
              ...plan.actividades.map((actividad) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: BentoCard(
                      backgroundColor: _kSurface,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  actividad.nombre,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _kText),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: _kAction,
                                    borderRadius: BorderRadius.circular(100)),
                                child: Text(
                                  actividad.nivelDificultad,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _kText),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(actividad.tipo,
                              style: const TextStyle(
                                  color: _kSubtext,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            actividad.instrucciones ??
                                'Sin instrucciones registradas.',
                            style:
                                const TextStyle(color: _kSubtext, height: 1.4),
                          ),
                          if (actividad.materiales.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: actividad.materiales
                                  .map(
                                    (m) => Chip(
                                      label: Text(m),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor:
                                          _kAction.withOpacity(0.35),
                                      side: BorderSide.none,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 16, color: _kSubtext.withOpacity(0.8)),
                              const SizedBox(width: 6),
                              Text(
                                  '${((actividad.duracionEstimada ?? 0) / 60).round()} min',
                                  style: const TextStyle(color: _kSubtext)),
                              const Spacer(),
                              ElevatedButton.icon(
                                onPressed: () => context.go(
                                  '/terapeuta/actividad/${actividad.id}?ninoId=${plan.ninoId}&planId=${plan.id}',
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Iniciar actividad'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kAction,
                                  foregroundColor: _kText,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(100)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
