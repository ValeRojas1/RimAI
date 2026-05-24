import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class FamilyPlanScreen extends ConsumerWidget {
  final String ninoId;

  const FamilyPlanScreen({super.key, required this.ninoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planActivoProvider(ninoId));

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Plan familiar',
        leadingIcon: Icons.arrow_back,
        iconColor: _kPrimary,
        onLeadingPressed: () => context.go('/familia/dashboard'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 96 + MediaQuery.of(context).padding.top,
          left: 24,
          right: 24,
          bottom: 48,
        ),
        child: planAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: _kPrimary)),
          error: (err, _) => BentoCard(
            backgroundColor: _kSurface,
            child: Text(
              'Aun no hay un plan publicado para ejecutar: $err',
              style: const TextStyle(color: _kSubtext, height: 1.35),
            ),
          ),
          data: (plan) {
            final totalSegundos = plan.actividades.fold<int>(
              0,
              (sum, item) => sum + (item.duracionEstimada ?? 0),
            );
            final requiereAcompanamiento =
                plan.actividades.any((a) => a.requiereAcompanamiento);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Plan de Actividades",
                  style: const TextStyle(
                    color: _kSubtext,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Sesión ${plan.sesionNumero} - ${plan.ninoNombre}",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _kText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${plan.actividades.length}/${plan.limiteActividades} actividades · ${(totalSegundos / 60).round()} min',
                  style: const TextStyle(color: _kSubtext),
                ),
                if (requiereAcompanamiento) ...[
                  const SizedBox(height: 20),
                  _AcompanamientoBanner(
                    nivelTea: plan.nivelTeaValidado,
                  ),
                ],
                const SizedBox(height: 24),
                ...plan.actividades.map(
                  (actividad) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _FamilyActivityCard(
                      actividad: actividad,
                      onStart: actividad.completada
                          ? null
                          : () => context.go(
                                '/familia/actividad/${actividad.id}?ninoId=${plan.ninoId}&planId=${plan.id}',
                              ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AcompanamientoBanner extends StatelessWidget {
  final int? nivelTea;

  const _AcompanamientoBanner({required this.nivelTea});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: const Color(0xFFFFF2CC),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.supervisor_account_outlined,
              color: Color(0xFF8A5A00)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nivel TEA validado: ${nivelTea ?? 'pendiente'}. Las actividades acompanadas deben realizarse con el tutor junto al niño.',
              style: const TextStyle(
                color: Color(0xFF6B4300),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyActivityCard extends StatelessWidget {
  final ActividadPlan actividad;
  final VoidCallback? onStart;

  const _FamilyActivityCard({
    required this.actividad,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final min = ((actividad.duracionEstimada ?? 0) / 60).round();
    final completed = actividad.completada;
    return AnimatedOpacity(
      opacity: completed ? 0.68 : 1,
      duration: const Duration(milliseconds: 180),
      child: BentoCard(
        backgroundColor: completed ? const Color(0xFFE8F5E9) : _kSurface,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    actividad.nombre,
                    style: const TextStyle(
                      color: _kText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (completed)
                  const Icon(Icons.check_circle, color: Color(0xFF2F6B45))
                else
                  Text(
                    '$min min',
                    style: const TextStyle(
                      color: _kSubtext,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              actividad.instrucciones ?? 'Sin instrucciones registradas.',
              style: const TextStyle(color: _kSubtext, height: 1.35),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(completed
                      ? 'Completada'
                      : 'Dificultad ${actividad.nivelDificultad}'),
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                ),
                Chip(
                  label: Text(actividad.requiereAcompanamiento
                      ? 'Acompanada'
                      : 'Autonoma'),
                  backgroundColor: actividad.requiereAcompanamiento
                      ? const Color(0xFFFFF2CC)
                      : const Color(0xFFE8F5E9),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onStart,
                icon: Icon(completed ? Icons.lock_outline : Icons.play_arrow),
                label: Text(
                    completed ? 'Actividad completada' : 'Ejecutar actividad'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAction,
                  foregroundColor: _kText,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
