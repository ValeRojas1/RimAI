import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';

// ── Design Tokens (PMV1) ─────────────────────────────────────────────────────
const _kPrimary = Color(0xFFA43714); // naranja terracota
const _kAction = Color(0xFFB8D6B2); // verde salvia
const _kBg = Color(0xFFFFF8F2); // fondo cálido
const _kSurface = Color(0xFFFAF2E9); // surface tarjetas
const _kText = Color(0xFF1E1B16); // texto principal
const _kSubtext = Color(0xFF58423B); // texto secundario
const _kBorder = Color(0xFFDFC0B7); // borde suave

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);
    final notifAsync = ref.watch(terapeutaNotificacionesProvider);
    final unreadCount =
        notifAsync.valueOrNull?.where((n) => !n.leido).length ?? 0;

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'RimAI',
        leadingIcon: Icons.all_inclusive,
        iconColor: _kPrimary,
        trailingWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text('$unreadCount'),
                backgroundColor: _kPrimary,
                child:
                    const Icon(Icons.notifications_outlined, color: _kSubtext),
              ),
              tooltip: 'Notificaciones',
              onPressed: () => _showNotifications(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: _kPrimary),
              tooltip: 'Cerrar sesión',
              onPressed: () async {
                await ref.read(authStorageProvider).clearSession();
                if (context.mounted) context.go('/auth/login');
              },
            ),
            const CircleAvatar(
              radius: 20,
              backgroundColor: _kSurface,
              child: Icon(Icons.person, color: _kSubtext),
            ),
          ],
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 0,
        onTap: (i) {
          final pacientes = dashboardAsync.valueOrNull?.pacientes ?? [];
          if (i == 1) {
            context.go('/terapeuta/planes');
            return;
          }
          if (pacientes.isEmpty) return;
          final first = pacientes.first;
          if (i == 2) context.go('/terapeuta/ia/${first.id}');
          if (i == 3) context.go('/terapeuta/progreso/${first.id}');
        },
        items: [
          BottomNavItem(icon: Icons.home_rounded, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Planes'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'Apoyo'),
          BottomNavItem(icon: Icons.insights, label: 'Progreso'),
        ],
      ),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
          ref.invalidate(pendientesProvider);
          ref.invalidate(terapeutaNotificacionesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: 96 + MediaQuery.of(context).padding.top,
            left: 24,
            right: 24,
            bottom: 120,
          ),
          child: dashboardAsync.when(
            loading: () => _buildSkeleton(),
            error: (err, _) {
              // Si la sesión expiró, redirigir automáticamente al login
              if (err is SessionExpiredException) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await ref.read(authStorageProvider).clearSession();
                  if (context.mounted) context.go('/auth/login');
                });
              }
              return _buildError(context, ref, err.toString(),
                  isSessionError: err is SessionExpiredException);
            },
            data: (data) => _buildContent(context, ref, data),
          ),
        ),
      ),
    );
  }

  // ── Content ────────────────────────────────────────────────────────────────

  void _showNotifications(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final async = ref.watch(terapeutaNotificacionesProvider);
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _kBorder,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Text(
                          'Notificaciones clinicas',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _kText,
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.notifications_active_outlined,
                            color: _kPrimary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: _kBorder),
                  Expanded(
                    child: async.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: _kPrimary),
                      ),
                      error: (err, _) => Center(
                        child: Text(
                          'Error al cargar notificaciones: $err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _kSubtext),
                        ),
                      ),
                      data: (items) {
                        if (items.isEmpty) {
                          return const Center(
                            child: Text(
                              'No hay notificaciones pendientes',
                              style: TextStyle(
                                color: _kSubtext,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final n = items[index];
                            final date = DateTime.tryParse(n.createdAt);
                            final isAlert = n.tipo == 'alerta_clinica';
                            return Opacity(
                              opacity: n.leido ? 0.65 : 1,
                              child: BentoCard(
                                padding: const EdgeInsets.all(16),
                                backgroundColor: Colors.white,
                                border: Border.all(
                                  color: isAlert
                                      ? _kPrimary.withValues(alpha: 0.25)
                                      : _kBorder,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          isAlert
                                              ? Icons.warning_amber_outlined
                                              : Icons.notifications_outlined,
                                          color:
                                              isAlert ? _kPrimary : _kSubtext,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            n.titulo,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: _kText,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        if (!n.leido)
                                          IconButton(
                                            tooltip: 'Marcar como leida',
                                            icon: const Icon(Icons.done,
                                                size: 18, color: _kPrimary),
                                            onPressed: () async {
                                              await ref
                                                  .read(
                                                      dashboardServiceProvider)
                                                  .marcarNotificacionTerapeutaLeida(
                                                      n.id);
                                              ref.invalidate(
                                                  terapeutaNotificacionesProvider);
                                              ref.invalidate(dashboardProvider);
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      n.mensaje,
                                      style: const TextStyle(
                                        color: _kSubtext,
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _tagSmall(n.canal),
                                        const SizedBox(width: 6),
                                        _tagSmall(n.estadoEnvio),
                                        const Spacer(),
                                        if (date != null)
                                          Text(
                                            DateFormat('dd MMM, HH:mm')
                                                .format(date),
                                            style: const TextStyle(
                                              color: _kSubtext,
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
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
            );
          },
        );
      },
    );
  }

  Widget _tagSmall(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _kBorder.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: _kSubtext),
        ),
      );

  Widget _buildContent(
      BuildContext context, WidgetRef ref, DashboardData data) {
    final pendientesAsync = ref.watch(pendientesProvider);
    final pendienteCount = pendientesAsync.valueOrNull?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGreeting(data),
        const SizedBox(height: 32),

        // ── Sección KPIs ─────────────────────────────────────────────────────
        const _SectionHeader(label: 'RESUMEN RÁPIDO'),
        const SizedBox(height: 16),
        _buildKPIRow(data),
        const SizedBox(height: 32),

        // ── Sección Accesos rápidos ─────────────────────────────────────
        const _SectionHeader(label: 'ACCESOS RÁPIDOS'),
        const SizedBox(height: 16),
        _buildQuickAccess(context, data),
        const SizedBox(height: 32),

        // ── Sección Solicitudes pendientes ──────────────────────────────
        if (pendienteCount > 0)
          ..._buildPendientesSection(context, ref, pendienteCount),
        if (pendienteCount > 0) const SizedBox(height: 32),

        // ── Sección Pacientes activos ──────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionHeader(label: 'MIS PACIENTES'),
            Text(
              '${data.totalPacientes} activos',
              style: const TextStyle(color: _kSubtext, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (data.pacientes.isEmpty)
          BentoCard(
            backgroundColor: _kSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aun no hay pacientes activos',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: _kText)),
                const SizedBox(height: 12),
                const Text(
                    'Registra o vincula el primer paciente para iniciar el plan terapeutico.',
                    style: TextStyle(color: _kSubtext)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/terapeuta/pendientes'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _kAction, foregroundColor: _kText),
                  child: const Text('Ver solicitudes'),
                ),
              ],
            ),
          )
        else
          ...data.pacientes.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PacienteCard(paciente: p),
              )),
      ],
    );
  }

  List<Widget> _buildPendientesSection(
      BuildContext context, WidgetRef ref, int count) {
    return [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          const _SectionHeader(label: 'SOLICITUDES PENDIENTES'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: _kPrimary, borderRadius: BorderRadius.circular(100)),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        GestureDetector(
          onTap: () => context.go('/terapeuta/pendientes'),
          child: const Text('Ver todos',
              style: TextStyle(
                  color: _kPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ]),
      const SizedBox(height: 12),
      BentoCard(
        backgroundColor: const Color(0xFFFDE8E8),
        child: Row(children: [
          const Icon(Icons.pending_actions_rounded, color: _kPrimary, size: 28),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  '$count ${count == 1 ? "niño espera" : "niños esperan"} ser vinculado${count == 1 ? "" : "s"}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _kText, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text('Revisa los expedientes y acepta la vinculación.',
                    style: TextStyle(color: _kSubtext, fontSize: 12)),
              ])),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => context.go('/terapeuta/pendientes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Revisar',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ]),
      ),
    ];
  }

  Widget _buildGreeting(DashboardData data) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 19
            ? 'Buenas tardes'
            : 'Buenas noches';
    final nombre = data.terapeutaNombre?.split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nombre == null ? greeting : '$greeting, $nombre',
          style: const TextStyle(fontSize: 14, color: _kSubtext),
        ),
        const SizedBox(height: 4),
        const Text(
          'Panel Terapéutico',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _kText,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildKPIRow(DashboardData data) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 480;
      final cards = [
        _MetricCard(
          label: 'PACIENTES',
          value: data.totalPacientes.toString(),
          icon: Icons.people_alt_rounded,
          accent: _kPrimary,
        ),
        _MetricCard(
          label: 'SESIONES',
          value: data.sesionesEstaSemana.toString(),
          icon: Icons.calendar_today_rounded,
          accent: _kPrimary,
          subtitle: 'esta semana',
        ),
        _MetricCard(
          label: 'ALERTAS',
          value: data.alertasBajaAdherencia.toString(),
          icon: Icons.warning_amber_rounded,
          accent: data.alertasBajaAdherencia > 0
              ? const Color(0xFFBA1A1A)
              : const Color(0xFF22C55E),
          subtitle: 'baja adherencia',
        ),
      ];

      if (isMobile) {
        return Column(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: c,
                  ))
              .toList(),
        );
      }
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: c,
                  ),
                ))
            .toList(),
      );
    });
  }

  Widget _buildQuickAccess(BuildContext context, DashboardData data) {
    final firstPatient =
        data.pacientes.isNotEmpty ? data.pacientes.first : null;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _QuickAccessButton(
          label: 'Apoyo clinico',
          icon: Icons.auto_awesome,
          onTap: () {
            if (firstPatient != null) {
              context.go('/terapeuta/ia/${firstPatient.id}');
            }
          },
        ),
        _QuickAccessButton(
          label: 'Vincular Paciente',
          icon: Icons.person_add_alt_1,
          onTap: () => context.go('/terapeuta/admision'),
        ),
        _QuickAccessButton(
          label: 'Nueva Sesión',
            icon: Icons.add_circle_outline_rounded,
            onTap: () {
              if (firstPatient != null) {
                context.push('/terapeuta/plan/${firstPatient.id}');
              }
            },
          ),
        _QuickAccessButton(
          label: 'Actividades',
          icon: Icons.fact_check_outlined,
          onTap: () => context.go('/terapeuta/actividades'),
        ),
        _QuickAccessButton(
          label: 'Ver progreso',
          icon: Icons.insights,
          onTap: () {
            if (firstPatient != null) {
              context.go('/terapeuta/progreso/${firstPatient.id}');
            }
          },
        ),
        if (data.pacientes.isNotEmpty)
          _QuickAccessButton(
            label: 'Validacion clinica',
            icon: Icons.verified_outlined,
            onTap: () =>
                context.go('/terapeuta/validacion/${data.pacientes.first.id}'),
          ),
      ],
    );
  }

  // ── States ─────────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _shimmerBox(120, double.infinity),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(child: _shimmerBox(100, double.infinity)),
            const SizedBox(width: 12),
            Expanded(child: _shimmerBox(100, double.infinity)),
            const SizedBox(width: 12),
            Expanded(child: _shimmerBox(100, double.infinity)),
          ],
        ),
        const SizedBox(height: 32),
        _shimmerBox(200, double.infinity),
        const SizedBox(height: 16),
        _shimmerBox(200, double.infinity),
      ],
    );
  }

  Widget _shimmerBox(double h, double w) => Container(
        height: h,
        width: w,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _kBorder.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
      );

  Widget _buildError(BuildContext context, WidgetRef ref, String err,
      {bool isSessionError = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSessionError
                ? Icons.lock_outline_rounded
                : Icons.cloud_off_rounded,
            size: 64,
            color: _kSubtext,
          ),
          const SizedBox(height: 16),
          Text(
            isSessionError
                ? 'Sesión expirada'
                : 'No se pudo conectar al servidor',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: _kText),
          ),
          const SizedBox(height: 8),
          Text(
            isSessionError
                ? 'Tu sesión ha expirado. Inicia sesión de nuevo.'
                : err,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _kSubtext),
          ),
          const SizedBox(height: 24),
          if (isSessionError)
            ElevatedButton.icon(
              onPressed: () async {
                await ref.read(authStorageProvider).clearSession();
                if (context.mounted) context.go('/auth/login');
              },
              icon: const Icon(Icons.login),
              label: const Text('Ir al Login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(dashboardProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: _kSubtext,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? subtitle;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      border: Border.all(color: _kBorder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _kSubtext,
                  letterSpacing: 1)),
          if (subtitle != null)
            Text(subtitle!,
                style: const TextStyle(fontSize: 12, color: _kSubtext)),
        ],
      ),
    );
  }
}

class _QuickAccessButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAccessButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: _kAction,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: _kAction.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _kText, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _kText,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PacienteCard extends ConsumerWidget {
  final PacienteDashboard paciente;
  const _PacienteCard({required this.paciente});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasa = paciente.ultimaSesion?.tasaAciertos;
    final tasaColor = tasa == null
        ? _kSubtext
        : tasa >= 0.8
            ? const Color(0xFF22C55E)
            : tasa >= 0.5
                ? const Color(0xFFD97706)
                : const Color(0xFFBA1A1A);
    final tasaLabel = tasa != null ? '${(tasa * 100).toInt()}%' : '--';
    final riskColor = _riskColor(paciente.riesgoAbandono.nivel);

    return BentoCard(
      padding: const EdgeInsets.all(24),
      backgroundColor: _kSurface,
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: _kAction.withValues(alpha: 0.4),
            child: Text(
              paciente.nombre.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paciente.nombre,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _kText,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _tag('${paciente.edad} años'),
                    _tag(paciente.nivelCognitivo),
                    _riskTag(paciente.riesgoAbandono.nivel, riskColor),
                  ],
                ),
                if (paciente.ultimaSesion?.fecha != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Última sesión: ${DateFormat('dd MMM yyyy').format(paciente.ultimaSesion!.fecha!)}',
                    style: const TextStyle(fontSize: 12, color: _kSubtext),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${paciente.riesgoAbandono.notaClinica} Factores: ${paciente.riesgoAbandono.factores.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _kSubtext),
                ),
              ],
            ),
          ),
          // Right side
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tasaLabel,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: tasaColor,
                ),
              ),
              const Text('precisión',
                  style: TextStyle(fontSize: 11, color: _kSubtext)),
              const SizedBox(height: 6),
              Text(
                '${paciente.riesgoAbandono.diasSinActividad} d sin act.',
                style: TextStyle(
                  fontSize: 11,
                  color: riskColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => context.go('/terapeuta/nino/${paciente.id}'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kAction,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'Ver perfil',
                    style: TextStyle(
                      color: _kText,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kBorder.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: _kSubtext),
      ),
    );
  }

  Color _riskColor(String nivel) {
    return switch (nivel.toLowerCase()) {
      'alto' => const Color(0xFFBA1A1A),
      'moderado' => const Color(0xFFD97706),
      _ => const Color(0xFF22C55E),
    };
  }

  Widget _riskTag(String nivel, Color color) {
    final label = nivel.isEmpty
        ? 'Bajo'
        : '${nivel.substring(0, 1).toUpperCase()}${nivel.substring(1).toLowerCase()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        'Riesgo $label',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
