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

class TherapeuticPlanScreen extends ConsumerStatefulWidget {
  final String ninoId;
  const TherapeuticPlanScreen({super.key, required this.ninoId});

  @override
  ConsumerState<TherapeuticPlanScreen> createState() =>
      _TherapeuticPlanScreenState();
}

class _TherapeuticPlanScreenState extends ConsumerState<TherapeuticPlanScreen> {
  final Set<String> _updating = {};
  final Set<String> _replacing = {};
  bool _isApproving = false;

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planActivoProvider(widget.ninoId));

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Plan terapeutico',
        leadingIcon: Icons.arrow_back,
        iconColor: _kPrimary,
        onLeadingPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/terapeuta/nino/${widget.ninoId}');
          }
        },
        trailingWidget: IconButton(
          tooltip: 'Inicio',
          icon: const Icon(Icons.home_rounded, color: _kSubtext),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 2) context.go('/terapeuta/ia/${widget.ninoId}');
          if (index == 3) context.go('/terapeuta/progreso/${widget.ninoId}');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Sesion'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'Apoyo'),
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
            child: Text(
              'No se pudo cargar el plan: $err',
              style: const TextStyle(color: _kSubtext),
            ),
          ),
          data: (plan) => Column(
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
                'Estado: ${plan.estadoPlan} · Nivel TEA: ${plan.nivelTeaValidado ?? 'pendiente'} · Nivel general: ${plan.nivelDificultadActual}',
                style: const TextStyle(color: _kSubtext),
              ),
              const SizedBox(height: 8),
              Text(
                'Reglas: maximo ${plan.limiteActividades} actividades y ${(plan.limiteDuracionSegundos / 60).round()} minutos antes de publicar.',
                style: const TextStyle(color: _kSubtext),
              ),
              if (plan.estadoPlan == 'borrador') ...[
                const SizedBox(height: 18),
                BentoCard(
                  backgroundColor: const Color(0xFFFFF2CC),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline, color: Color(0xFF8A5A00)),
                          SizedBox(width: 10),
                          Text(
                            'Plan en Borrador',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6B4300),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Este plan de actividades aún no ha sido aprobado por ti. El tutor/padre no podrá visualizar ni ejecutar las actividades de esta sesión en la app familiar hasta que lo apruebes.',
                        style: TextStyle(
                          color: Color(0xFF6B4300),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _isApproving ? null : () => _aprobarPlan(plan.id),
                          icon: _isApproving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1E1B16),
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_isApproving
                              ? 'Aprobando sesión...'
                              : 'Aprobar y Publicar Sesión'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB8D6B2),
                            foregroundColor: const Color(0xFF1E1B16),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              ...plan.actividades.map(
                (actividad) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ActivityCard(
                    plan: plan,
                    actividad: actividad,
                    updating: _updating.contains(actividad.id),
                    replacing: _replacing.contains(actividad.id),
                    onStart: () => context.go(
                      '/terapeuta/actividad/${actividad.id}?ninoId=${plan.ninoId}&planId=${plan.id}',
                    ),
                    onReplace: () => _showReplaceActivity(plan, actividad),
                    onDifficultyChanged: (nivel) => _actualizarDificultad(
                      planId: plan.id,
                      actividadId: actividad.id,
                      nivel: nivel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aprobarPlan(String planId) async {
    setState(() => _isApproving = true);
    try {
      await ref.read(dashboardServiceProvider).actualizarEstadoPlan(
            planId: planId,
            estado: 'publicado',
            observacion:
                'Aprobado y publicado por el terapeuta desde el plan clínico',
          );
      ref.invalidate(planActivoProvider(widget.ninoId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '¡Plan de sesión aprobado y publicado con éxito! El tutor ya puede verlo.'),
          backgroundColor: Color(0xFF2F6B45),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo aprobar el plan: $e'),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  Future<void> _actualizarDificultad({
    required String planId,
    required String actividadId,
    required String nivel,
  }) async {
    setState(() => _updating.add(actividadId));
    try {
      await ref.read(dashboardServiceProvider).actualizarDificultadActividad(
            planId: planId,
            actividadId: actividadId,
            nivelDificultad: nivel,
            origen: 'manual_plan',
            observacion: 'Ajuste manual desde plan terapeutico',
          );
      ref.invalidate(planActivoProvider(widget.ninoId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dificultad actualizada a $nivel.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar dificultad: $e')),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(actividadId));
    }
  }

  Future<void> _showReplaceActivity(
    PlanData plan,
    ActividadPlan actividadActual,
  ) async {
    final selected = await showModalBottomSheet<ActividadCatalogo>(
      context: context,
      backgroundColor: _kBg,
      isScrollControlled: true,
      builder: (context) {
        return _ReplaceActivitySheet(
          planId: plan.id,
          currentActivityId: actividadActual.id,
        );
      },
    );
    if (selected == null) return;
    await _reemplazarActividad(
      planId: plan.id,
      actividadId: actividadActual.id,
      nuevaActividadId: selected.id,
      nuevaActividadNombre: selected.nombre,
    );
  }

  Future<void> _reemplazarActividad({
    required String planId,
    required String actividadId,
    required String nuevaActividadId,
    required String nuevaActividadNombre,
  }) async {
    setState(() => _replacing.add(actividadId));
    try {
      await ref.read(dashboardServiceProvider).reemplazarActividadEnPlan(
            planId: planId,
            actividadId: actividadId,
            nuevaActividadId: nuevaActividadId,
          );
      ref.invalidate(planActivoProvider(widget.ninoId));
      ref.invalidate(actividadesCatalogoProvider(planId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Actividad cambiada por $nuevaActividadNombre.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar la actividad: $e')),
      );
    } finally {
      if (mounted) setState(() => _replacing.remove(actividadId));
    }
  }
}

class _ActivityCard extends StatelessWidget {
  final PlanData plan;
  final ActividadPlan actividad;
  final bool updating;
  final bool replacing;
  final VoidCallback onStart;
  final VoidCallback onReplace;
  final ValueChanged<String> onDifficultyChanged;

  const _ActivityCard({
    required this.plan,
    required this.actividad,
    required this.updating,
    required this.replacing,
    required this.onStart,
    required this.onReplace,
    required this.onDifficultyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BentoCard(
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
                    color: _kText,
                  ),
                ),
              ),
              _DifficultyBadge(nivel: actividad.nivelDificultad),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            actividad.tipo,
            style: const TextStyle(
              color: _kSubtext,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            actividad.instrucciones ?? 'Sin instrucciones registradas.',
            style: const TextStyle(color: _kSubtext, height: 1.4),
          ),
          const SizedBox(height: 12),
          _ExecutionModeNotice(actividad: actividad),
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
                      backgroundColor: _kAction.withValues(alpha: 0.35),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: actividad.nivelDificultad,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Dificultad en este plan',
              prefixIcon: updating
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.tune),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const ['Bajo', 'Medio', 'Alto']
                .map(
                  (nivel) => DropdownMenuItem(
                    value: nivel,
                    child: Text(nivel),
                  ),
                )
                .toList(),
            onChanged: updating
                ? null
                : (value) {
                    if (value == null || value == actividad.nivelDificultad) {
                      return;
                    }
                    onDifficultyChanged(value);
                  },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: _kSubtext,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${((actividad.duracionEstimada ?? 0) / 60).round()} min',
                    style: const TextStyle(color: _kSubtext),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Previsualizar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAction,
                  foregroundColor: _kText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: replacing ? null : onReplace,
                icon: replacing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz),
                label: Text(replacing ? 'Cambiando...' : 'Cambiar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: Color(0xFFDFC0B7)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplaceActivitySheet extends ConsumerWidget {
  final String planId;
  final String currentActivityId;

  const _ReplaceActivitySheet({
    required this.planId,
    required this.currentActivityId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actividadesAsync = ref.watch(actividadesCatalogoProvider(planId));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cambiar actividad',
              style: TextStyle(
                color: _kText,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Selecciona una actividad del catalogo que aun no este en este plan.',
              style: TextStyle(color: _kSubtext, height: 1.35),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.62,
              ),
              child: actividadesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _kPrimary),
                ),
                error: (error, _) => Text(
                  'No se pudo cargar el catalogo: $error',
                  style: const TextStyle(color: _kSubtext),
                ),
                data: (items) {
                  final available = items
                      .where((item) =>
                          item.id != currentActivityId && !item.asociado)
                      .toList();
                  if (available.isEmpty) {
                    return const Text(
                      'No hay actividades disponibles para reemplazar en este momento.',
                      style: TextStyle(color: _kSubtext),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: available.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = available[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).pop(item),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Icon(Icons.add_circle_outline,
                                    color: _kPrimary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.nombre,
                                        style: const TextStyle(
                                          color: _kText,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${item.categoria} · ${(item.duracionEstimada / 60).round()} min · ${item.nivelDificultad}',
                                        style: const TextStyle(
                                          color: _kSubtext,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  final String nivel;

  const _DifficultyBadge({required this.nivel});

  @override
  Widget build(BuildContext context) {
    final color = switch (nivel) {
      'Alto' => const Color(0xFFBA1A1A),
      'Medio' => const Color(0xFFD97706),
      _ => const Color(0xFF2F6B45),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        'Actual: $nivel',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _ExecutionModeNotice extends StatelessWidget {
  final ActividadPlan actividad;

  const _ExecutionModeNotice({required this.actividad});

  @override
  Widget build(BuildContext context) {
    final requiere = actividad.requiereAcompanamiento;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: requiere ? const Color(0xFFFFF2CC) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: requiere ? const Color(0xFFE2A300) : const Color(0xFF7CB985),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            requiere ? Icons.supervisor_account_outlined : Icons.person_outline,
            color: requiere ? const Color(0xFF8A5A00) : const Color(0xFF2F6B45),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              requiere
                  ? 'Ejecucion acompanada: el tutor debe realizar esta actividad con el niño.'
                  : 'Ejecucion autonoma: el niño puede realizarla con supervision ligera.',
              style: TextStyle(
                color: requiere
                    ? const Color(0xFF6B4300)
                    : const Color(0xFF2F6B45),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
