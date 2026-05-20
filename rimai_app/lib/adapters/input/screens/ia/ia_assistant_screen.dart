import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class IAAssistantScreen extends ConsumerStatefulWidget {
  final String? ninoId;

  const IAAssistantScreen({super.key, this.ninoId});

  @override
  ConsumerState<IAAssistantScreen> createState() => _IAAssistantScreenState();
}

class _IAAssistantScreenState extends ConsumerState<IAAssistantScreen> {
  final _observationController = TextEditingController();

  @override
  void dispose() {
    _observationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ninoId = widget.ninoId;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: ninoId != null,
      appBar: const RimAITopBar(
        title: 'Asistente IA',
        leadingIcon: Icons.psychology,
        iconColor: Color(0xFF4A624D),
      ),
      bottomNavigationBar: ninoId == null
          ? null
          : RimAIBottomNav(
              currentIndex: 2,
              onTap: (index) {
                if (index == 0) context.go('/terapeuta/dashboard');
                if (index == 1) context.go('/terapeuta/plan/$ninoId');
                if (index == 3) context.go('/terapeuta/progreso/$ninoId');
              },
              items: [
                BottomNavItem(icon: Icons.home, label: 'Inicio'),
                BottomNavItem(icon: Icons.assignment, label: 'Plan'),
                BottomNavItem(icon: Icons.auto_awesome, label: 'IA'),
                BottomNavItem(icon: Icons.insights, label: 'Progreso'),
              ],
            ),
      body: ninoId == null
          ? const Center(
              child: Text('Selecciona un paciente desde el dashboard.'))
          : _AssistantContent(
              ninoId: ninoId,
              observationController: _observationController,
            ),
    );
  }
}

class _AssistantContent extends ConsumerWidget {
  final String ninoId;
  final TextEditingController observationController;

  const _AssistantContent({
    required this.ninoId,
    required this.observationController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assistantAsync = ref.watch(iaAssistantProvider(ninoId));

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: 96 + MediaQuery.of(context).padding.top,
        left: 24,
        right: 24,
        bottom: 120,
      ),
      child: assistantAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF4A624D)),
        ),
        error: (error, _) => BentoCard(
          backgroundColor: const Color(0xFFFAF2E9),
          child: Text(
            'No se pudo cargar el asistente IA: $error',
            style: const TextStyle(color: Color(0xFF58423B)),
          ),
        ),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.ninoNombre,
              style: const TextStyle(
                color: Color(0xFF58423B),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Asistente IA',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E1B16),
              ),
            ),
            const SizedBox(height: 24),
            _AnalysisCard(data: data),
            const SizedBox(height: 24),
            _RecommendationsCard(
              ninoId: ninoId,
              recomendaciones: data.recomendaciones,
              observationController: observationController,
            ),
            const SizedBox(height: 24),
            _SessionPlanCard(planSesion: data.planSesion),
          ],
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final IAAssistantData data;

  const _AnalysisCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analisis cognitivo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: data.analisis.cargaCognitiva.clamp(0, 1),
            minHeight: 10,
            color: const Color(0xFF4A624D),
            backgroundColor: const Color(0xFFE9E1D8),
          ),
          const SizedBox(height: 12),
          Text(
              'Carga cognitiva: ${(data.analisis.cargaCognitiva * 100).round()}%'),
          Text('Foco estimado: ${data.analisis.focoEstimado}'),
          Text('Nivel de calma: ${data.analisis.nivelCalma}/10'),
        ],
      ),
    );
  }
}

class _RecommendationsCard extends ConsumerWidget {
  final String ninoId;
  final List<RecomendacionClinica> recomendaciones;
  final TextEditingController observationController;

  const _RecommendationsCard({
    required this.ninoId,
    required this.recomendaciones,
    required this.observationController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recomendaciones',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (recomendaciones.isEmpty)
            const Text(
                'No hay recomendaciones disponibles para este paciente.'),
          ...recomendaciones.map(
            (rec) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.actividad,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(rec.justificacion),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Confianza ${(rec.confianza * 100).round()}%'),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _registrarDecision(
                          context,
                          ref,
                          rec.id,
                          'RECHAZADA',
                        ),
                        child: const Text('Rechazar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _registrarDecision(
                          context,
                          ref,
                          rec.id,
                          'ACEPTADA',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A624D),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Aceptar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: observationController,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Observaciones clinicas',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _registrarDecision(
    BuildContext context,
    WidgetRef ref,
    String recomendacionId,
    String accion,
  ) async {
    await ref.read(registrarDecisionProvider).ejecutar(
          recomendacionId,
          accion,
          observationController.text,
          ninoId: ninoId,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Decision $accion registrada.')),
    );
  }
}

class _SessionPlanCard extends StatelessWidget {
  final List<SessionStep> planSesion;

  const _SessionPlanCard({required this.planSesion});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Plan de sesion',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (planSesion.isEmpty)
            const Text('No hay pasos sugeridos para la sesion.'),
          ...planSesion.map(
            (step) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(step.title),
              subtitle: Text('${step.description}\n${step.duration}'),
              isThreeLine: true,
            ),
          ),
        ],
      ),
    );
  }
}
