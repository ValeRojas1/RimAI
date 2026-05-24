import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

enum TherapistPatientDestination { plan, apoyo, progreso }

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);
const _kBorder = Color(0xFFDFC0B7);

class TherapistPatientSelectorScreen extends ConsumerWidget {
  final TherapistPatientDestination destination;

  const TherapistPatientSelectorScreen({
    super.key,
    required this.destination,
  });

  int get _currentIndex => switch (destination) {
        TherapistPatientDestination.plan => 1,
        TherapistPatientDestination.apoyo => 2,
        TherapistPatientDestination.progreso => 3,
      };

  String get _title => switch (destination) {
        TherapistPatientDestination.plan => 'Planes terapeuticos',
        TherapistPatientDestination.apoyo => 'Apoyo clinico',
        TherapistPatientDestination.progreso => 'Progreso clinico',
      };

  String get _subtitle => switch (destination) {
        TherapistPatientDestination.plan =>
          'Selecciona un paciente para revisar su plan terapeutico.',
        TherapistPatientDestination.apoyo =>
          'Selecciona un paciente para revisar recomendaciones y contexto.',
        TherapistPatientDestination.progreso =>
          'Selecciona un paciente para revisar sus metricas de avance.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: _title,
        leadingIcon: Icons.people_alt_outlined,
        iconColor: _kPrimary,
        trailingWidget: IconButton(
          tooltip: 'Inicio',
          icon: const Icon(Icons.home_rounded, color: _kSubtext),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 1) context.go('/terapeuta/planes');
          if (index == 2) context.go('/terapeuta/ia');
          if (index == 3) context.go('/terapeuta/progreso');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Sesion'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'Apoyo'),
          BottomNavItem(icon: Icons.insights, label: 'Progreso'),
        ],
      ),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: () async => ref.invalidate(dashboardProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: 96 + MediaQuery.of(context).padding.top,
            left: 24,
            right: 24,
            bottom: 120,
          ),
          child: dashboardAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            ),
            error: (err, _) => _MessageCard(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar los pacientes',
              message: err.toString(),
            ),
            data: (data) {
              if (data.pacientes.isEmpty) {
                return const _MessageCard(
                  icon: Icons.person_search_outlined,
                  title: 'Sin pacientes asignados',
                  message:
                      'Cuando aceptes o vincules pacientes, apareceran aqui.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    style: const TextStyle(color: _kSubtext, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  ...data.pacientes.map(
                    (paciente) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PatientActionCard(
                        paciente: paciente,
                        destination: destination,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PatientActionCard extends StatelessWidget {
  final PacienteDashboard paciente;
  final TherapistPatientDestination destination;

  const _PatientActionCard({
    required this.paciente,
    required this.destination,
  });

  String get _actionLabel => switch (destination) {
        TherapistPatientDestination.plan => 'Ver plan terapeutico',
        TherapistPatientDestination.apoyo => 'Abrir apoyo clinico',
        TherapistPatientDestination.progreso => 'Ver progreso',
      };

  String _targetRoute() => switch (destination) {
        TherapistPatientDestination.plan => '/terapeuta/plan/${paciente.id}',
        TherapistPatientDestination.apoyo => '/terapeuta/ia/${paciente.id}',
        TherapistPatientDestination.progreso =>
          '/terapeuta/progreso/${paciente.id}',
      };

  @override
  Widget build(BuildContext context) {
    final hasPlan = paciente.planActivoId != null ||
        paciente.estadoClinico == 'plan_activo';
    final planPending = destination == TherapistPatientDestination.plan &&
        !hasPlan &&
        paciente.estadoClinico != 'listo_para_plan';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _kAction.withValues(alpha: 0.45),
                child: Text(
                  (paciente.nombre.isNotEmpty ? paciente.nombre[0] : '?')
                      .toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kText,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paciente.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${paciente.edad} anos - ${_estadoLabel(paciente.estadoClinico)}',
                      style: const TextStyle(color: _kSubtext, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/terapeuta/nino/${paciente.id}'),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Perfil'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kSubtext,
                    side: const BorderSide(color: _kBorder),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      planPending ? null : () => context.push(_targetRoute()),
                  icon: Icon(_actionIcon, size: 18),
                  label: Text(_actionLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kBorder,
                    disabledForegroundColor: _kSubtext,
                  ),
                ),
              ),
            ],
          ),
          if (planPending) ...[
            const SizedBox(height: 10),
            const Text(
              'Primero valida el perfil clinico y genera un plan para este paciente.',
              style: TextStyle(color: _kSubtext, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  IconData get _actionIcon => switch (destination) {
        TherapistPatientDestination.plan => Icons.assignment_outlined,
        TherapistPatientDestination.apoyo => Icons.auto_awesome,
        TherapistPatientDestination.progreso => Icons.insights,
      };

  String _estadoLabel(String estado) => switch (estado) {
        'plan_activo' => 'plan activo',
        'listo_para_plan' => 'listo para plan',
        'vinculado_terapeuta' => 'perfil en validacion',
        'perfil_clinico_incompleto' => 'perfil incompleto',
        _ => 'en seguimiento',
      };
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _kPrimary, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _kText,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: _kSubtext, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
