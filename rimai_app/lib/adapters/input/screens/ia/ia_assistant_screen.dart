import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

final DateFormat _kFechaFmt = DateFormat('dd/MM/yyyy');
final DateFormat _kHoraFmt = DateFormat('HH:mm');

String _fmtFecha(DateTime? dt) =>
    dt == null ? '—' : _kFechaFmt.format(dt.toLocal());

String _fmtHora(DateTime? dt) =>
    dt == null ? '—' : _kHoraFmt.format(dt.toLocal());

String _fmtFechaHora(DateTime? dt) =>
    dt == null ? '—' : '${_fmtFecha(dt)} · ${_fmtHora(dt)}';

String _fmtDuracion(num? segundos) {
  final s = (segundos ?? 0).round();
  if (s <= 0) return '—';
  final min = s ~/ 60;
  final rem = s % 60;
  if (min <= 0) return '${rem}s';
  if (rem == 0) return '$min min';
  return '$min min ${rem}s';
}

String _fmtRangoHoras(DateTime? inicio, DateTime? fin) {
  if (inicio == null && fin == null) return '';
  if (inicio != null && fin != null) {
    return '${_fmtHora(inicio)} – ${_fmtHora(fin)}';
  }
  return _fmtHora(inicio ?? fin);
}

class IAAssistantScreen extends ConsumerStatefulWidget {
  final String? ninoId;

  const IAAssistantScreen({super.key, this.ninoId});

  @override
  ConsumerState<IAAssistantScreen> createState() => _IAAssistantScreenState();
}

class _IAAssistantScreenState extends ConsumerState<IAAssistantScreen> {
  @override
  Widget build(BuildContext context) {
    final ninoId = widget.ninoId;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: ninoId != null,
      appBar: RimAITopBar(
        title: 'Apoyo clinico',
        leadingIcon: Icons.arrow_back,
        iconColor: const Color(0xFF4A624D),
        onLeadingPressed: () {
          if (context.canPop()) {
            context.pop();
          } else if (ninoId != null) {
            context.go('/terapeuta/nino/$ninoId');
          } else {
            context.go('/terapeuta/dashboard');
          }
        },
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
                BottomNavItem(icon: Icons.spatial_audio_off, label: 'Sesion'),
                BottomNavItem(icon: Icons.auto_awesome, label: 'Apoyo'),
                BottomNavItem(icon: Icons.insights, label: 'Progreso'),
              ],
            ),
      body: ninoId == null
          ? const Center(
              child: Text('Selecciona un paciente desde el dashboard.'))
          : _AssistantContent(
              ninoId: ninoId,
            ),
    );
  }
}

class _AssistantContent extends ConsumerWidget {
  final String ninoId;

  const _AssistantContent({
    required this.ninoId,
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
            'No se pudo cargar el apoyo clinico: $error',
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
            Text(
              'Apoyo clinico de ${data.ninoNombre}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E1B16),
              ),
            ),
            const SizedBox(height: 24),
            _AnalysisCard(data: data),
            const SizedBox(height: 24),
            _SessionReviewCard(ninoId: ninoId),
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
            'Analisis del paciente',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Estimacion basada en el plan vigente y los resultados recientes registrados para este paciente.',
            style: TextStyle(color: Color(0xFF58423B), height: 1.35),
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

class _SessionReviewCard extends ConsumerStatefulWidget {
  final String ninoId;

  const _SessionReviewCard({required this.ninoId});

  @override
  ConsumerState<_SessionReviewCard> createState() => _SessionReviewCardState();
}

class _SessionReviewCardState extends ConsumerState<_SessionReviewCard> {
  final Set<String> _resolving = {};

  @override
  Widget build(BuildContext context) {
    final sesionesAsync = ref.watch(sesionesRevisionProvider(widget.ninoId));

    return BentoCard(
      backgroundColor: Colors.white,
      child: sesionesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF4A624D)),
        ),
        error: (error, _) => Text(
          'No se pudieron cargar las sesiones por revisar: $error',
          style: const TextStyle(color: Color(0xFF58423B)),
        ),
        data: (sesiones) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recomendaciones para revisar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cada bloque corresponde a una sesion completada por la familia. Revisa el resultado de cada actividad y aprueba solo los ajustes solicitados que correspondan.',
              style: TextStyle(color: Color(0xFF58423B), height: 1.35),
            ),
            const SizedBox(height: 16),
            if (sesiones.isEmpty)
              const Text(
                'Aun no hay sesiones completadas para revisar.',
                style: TextStyle(color: Color(0xFF58423B), height: 1.35),
              ),
            ..._buildSessionBlocks(sesiones),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSessionBlocks(List<SesionRevisionData> sesiones) {
    var activityNumber = 1;
    return sesiones.map((sesion) {
      final startNumber = activityNumber;
      activityNumber += sesion.actividades.length;
      return _buildSessionBlock(sesion, startNumber);
    }).toList();
  }

  Widget _buildSessionBlock(SesionRevisionData sesion, int startNumber) {
    final pct = (sesion.tasaAciertos * 100).round();
    final activityCount = sesion.actividades.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF2E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesion de apoyo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E1B16),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Actividades completadas por la familia',
                      style: TextStyle(
                        color: Color(0xFF58423B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$pct% aciertos',
                  style: const TextStyle(
                    color: Color(0xFF4A624D),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSessionMeta(sesion),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$activityCount ${activityCount == 1 ? 'actividad realizada' : 'actividades realizadas'}',
                  style:
                      const TextStyle(color: Color(0xFF58423B), fontSize: 12),
                ),
              ),
              if (sesion.actividades.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showSessionDetails(sesion, startNumber),
                  icon: const Icon(Icons.schedule,
                      size: 16, color: Color(0xFF4A624D)),
                  label: const Text('Ver detalles'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4A624D),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...sesion.actividades.asMap().entries.map(
                (entry) => _buildActivityReview(
                  entry.value,
                  startNumber + entry.key,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSessionMeta(SesionRevisionData sesion) {
    final inicio = sesion.inicioEfectivo;
    final fin = sesion.fechaFin;
    final rango = _fmtRangoHoras(inicio, fin);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _metaChip(Icons.event, _fmtFecha(inicio)),
        if (rango.isNotEmpty) _metaChip(Icons.schedule, rango),
      ],
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF4A624D)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF58423B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionDetails(SesionRevisionData sesion, int startNumber) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionDetailsSheet(
        sesion: sesion,
        startNumber: startNumber,
      ),
    );
  }

  Widget _buildActivityReview(
    ActividadRevisionSesion actividad,
    int activityNumber,
  ) {
    final solicitud = actividad.solicitudAjuste;
    final pct = (actividad.tasaAciertos * 100).round();
    final ayuda = switch (actividad.nivelAyudaRequerido) {
      1 => 'Verbal',
      2 => 'Fisica',
      _ => 'Ninguna',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF2E9),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: const Color(0xFFE9E1D8)),
                ),
                child: Text(
                  'Actividad $activityNumber',
                  style: const TextStyle(
                    color: Color(0xFF4A624D),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  actividad.actividadNombre,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${actividad.aciertos}/${actividad.intentos} aciertos ($pct%) · Dificultad usada: ${actividad.nivelDificultadUsado} · Ayuda: $ayuda',
            style: const TextStyle(color: Color(0xFF58423B), height: 1.3),
          ),
          if (actividad.iniciadoEn != null || actividad.completadoEn != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule, size: 13, color: Color(0xFF8C7B72)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Inicio ${_fmtHora(actividad.iniciadoEn)} · Fin ${_fmtHora(actividad.completadoEn)} · ${_fmtDuracion(actividad.duracionSegundos)}',
                    style: const TextStyle(
                      color: Color(0xFF8C7B72),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (actividad.observaciones?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              actividad.observaciones!,
              style: const TextStyle(color: Color(0xFF58423B), height: 1.3),
            ),
          ],
          if (solicitud != null) ...[
            const SizedBox(height: 12),
            _buildSolicitud(solicitud),
          ],
        ],
      ),
    );
  }

  Widget _buildSolicitud(SolicitudAjusteData solicitud) {
    final pending = solicitud.estado == 'pendiente';
    final accion = solicitud.accion == 'reducir' ? 'reducir' : 'aumentar';
    final resolving = _resolving.contains(solicitud.id);
    final approved = solicitud.estado == 'aprobada';
    final statusColor = pending
        ? const Color(0xFFFFF2CC)
        : approved
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEDEA);
    final statusBorderColor = pending
        ? const Color(0xFFF1D88A)
        : approved
            ? const Color(0xFFC8E6C9)
            : const Color(0xFFF3C2BC);
    final statusText = pending
        ? 'Solicitud para $accion dificultad'
        : approved
            ? 'Solicitud aprobada'
            : 'Solicitud rechazada';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusText,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1B16),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${solicitud.dificultadActual} -> ${solicitud.dificultadSugerida}',
            style: const TextStyle(color: Color(0xFF58423B)),
          ),
          if (solicitud.solicitadaEn != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule, size: 13, color: Color(0xFF8C7B72)),
                const SizedBox(width: 6),
                Text(
                  'Solicitada el ${_fmtFechaHora(solicitud.solicitadaEn)}',
                  style:
                      const TextStyle(color: Color(0xFF8C7B72), fontSize: 12),
                ),
              ],
            ),
          ],
          if (pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 11,
                  child: OutlinedButton(
                    onPressed:
                        resolving ? null : () => _resolver(solicitud, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Rechazar',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 10,
                  child: ElevatedButton(
                    onPressed:
                        resolving ? null : () => _resolver(solicitud, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A624D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        resolving ? 'Guardando...' : 'Aprobar',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resolver(SolicitudAjusteData solicitud, bool aceptar) async {
    setState(() => _resolving.add(solicitud.id));
    try {
      await ref.read(iaServiceProvider).resolverSolicitudAjuste(
            solicitud.id,
            aceptar: aceptar,
          );
      ref.invalidate(sesionesRevisionProvider(widget.ninoId));
      ref.invalidate(planActivoProvider(widget.ninoId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              aceptar ? 'Ajuste aprobado y aplicado.' : 'Solicitud rechazada.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo resolver la solicitud: $e')),
      );
    } finally {
      if (mounted) setState(() => _resolving.remove(solicitud.id));
    }
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
            'Pasos sugeridos para la sesion',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (planSesion.isEmpty)
            const Text(
              'No hay pasos sugeridos porque el paciente aun no tiene actividades listas en su plan.',
              style: TextStyle(color: Color(0xFF58423B), height: 1.35),
            ),
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

class _SessionDetailsSheet extends StatelessWidget {
  final SesionRevisionData sesion;
  final int startNumber;

  const _SessionDetailsSheet({
    required this.sesion,
    required this.startNumber,
  });

  String get _duracionTotal {
    final inicio = sesion.inicioEfectivo;
    final fin = sesion.fechaFin;
    if (inicio != null && fin != null) {
      final secs = fin.difference(inicio).inSeconds;
      if (secs > 0) return _fmtDuracion(secs);
    }
    final suma = sesion.actividades
        .fold<double>(0, (acc, a) => acc + a.duracionSegundos);
    return _fmtDuracion(suma);
  }

  @override
  Widget build(BuildContext context) {
    final pct = (sesion.tasaAciertos * 100).round();
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFF8F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0D5C8),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detalle de la sesion',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E1B16),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Sesion N.${sesion.sesionNumero} · ${_fmtFecha(sesion.inicioEfectivo)}',
                            style: const TextStyle(
                              color: Color(0xFF58423B),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFF58423B)),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    Row(
                      children: [
                        _summaryTile(
                          icon: Icons.play_circle_outline,
                          label: 'Inicio',
                          value: _fmtHora(sesion.inicioEfectivo),
                        ),
                        const SizedBox(width: 10),
                        _summaryTile(
                          icon: Icons.stop_circle_outlined,
                          label: 'Fin',
                          value: _fmtHora(sesion.fechaFin),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _summaryTile(
                          icon: Icons.timelapse,
                          label: 'Duracion',
                          value: _duracionTotal,
                        ),
                        const SizedBox(width: 10),
                        _summaryTile(
                          icon: Icons.adjust,
                          label: 'Aciertos',
                          value: '$pct%',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Cronologia de actividades',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E1B16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...sesion.actividades.asMap().entries.map(
                          (entry) => _ActivityTimelineItem(
                            actividad: entry.value,
                            numero: startNumber + entry.key,
                            esUltima: entry.key == sesion.actividades.length - 1,
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9E1D8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: const Color(0xFF4A624D)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8C7B72),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E1B16),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTimelineItem extends StatelessWidget {
  final ActividadRevisionSesion actividad;
  final int numero;
  final bool esUltima;

  const _ActivityTimelineItem({
    required this.actividad,
    required this.numero,
    required this.esUltima,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (actividad.tasaAciertos * 100).round();
    final ayuda = switch (actividad.nivelAyudaRequerido) {
      1 => 'Verbal',
      2 => 'Fisica',
      _ => 'Ninguna',
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF4A624D),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$numero',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!esUltima)
                Expanded(
                  child: Container(
                    width: 2,
                    color: const Color(0xFFE0D5C8),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE9E1D8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actividad.actividadNombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1B16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _detailRow(
                    Icons.play_arrow,
                    'Inicio',
                    _fmtHora(actividad.iniciadoEn),
                  ),
                  _detailRow(
                    Icons.flag_outlined,
                    'Fin',
                    _fmtHora(actividad.completadoEn),
                  ),
                  _detailRow(
                    Icons.timelapse,
                    'Duracion',
                    _fmtDuracion(actividad.duracionSegundos),
                  ),
                  const Divider(height: 18, color: Color(0xFFF0E8DE)),
                  Text(
                    '${actividad.aciertos}/${actividad.intentos} aciertos ($pct%) · Dificultad: ${actividad.nivelDificultadUsado} · Ayuda: $ayuda',
                    style: const TextStyle(
                      color: Color(0xFF58423B),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  if (actividad.observaciones?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      actividad.observaciones!,
                      style: const TextStyle(
                        color: Color(0xFF8C7B72),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (actividad.solicitudAjuste?.solicitadaEn != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.tune,
                            size: 13, color: Color(0xFF8C7B72)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ajuste solicitado el ${_fmtFechaHora(actividad.solicitudAjuste!.solicitadaEn)}',
                            style: const TextStyle(
                              color: Color(0xFF8C7B72),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF4A624D)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFF8C7B72),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E1B16),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
