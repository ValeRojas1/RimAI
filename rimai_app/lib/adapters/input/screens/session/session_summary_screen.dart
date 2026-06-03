import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class SessionSummaryScreen extends ConsumerStatefulWidget {
  final int totalAciertos;
  final int totalIntentos;
  final int segundosTranscurridos;
  final String nivelAyuda;
  final String ninoNombre;
  final String? observaciones;
  final String? ninoId;
  final String? planId;
  final String? sesionId;
  final int? sesionNumero;
  final String? nivelDificultadRecomendado;
  final List<Map<String, dynamic>> ajustesDificultad;
  final bool permitirAplicarSugerencia;
  final bool pendienteSync;

  const SessionSummaryScreen({
    super.key,
    required this.totalAciertos,
    required this.totalIntentos,
    required this.segundosTranscurridos,
    required this.nivelAyuda,
    this.ninoNombre = 'Paciente',
    this.observaciones,
    this.ninoId,
    this.planId,
    this.sesionId,
    this.sesionNumero,
    this.nivelDificultadRecomendado,
    this.ajustesDificultad = const [],
    this.permitirAplicarSugerencia = true,
    this.pendienteSync = false,
  });

  @override
  ConsumerState<SessionSummaryScreen> createState() =>
      _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends ConsumerState<SessionSummaryScreen> {
  bool _applying = false;
  bool _requesting = false;
  String? _appliedLevel;
  String? _requestStatus;

  @override
  Widget build(BuildContext context) {
    final isFamilyRoute =
        GoRouterState.of(context).uri.path.startsWith('/familia');
    final tasa = widget.totalIntentos > 0
        ? widget.totalAciertos / widget.totalIntentos
        : 0.0;
    final tasaColor = tasa >= 0.8
        ? const Color(0xFF22C55E)
        : tasa >= 0.5
            ? const Color(0xFFD97706)
            : const Color(0xFFBA1A1A);

    final minutos = (widget.segundosTranscurridos / 60).floor();
    final segundos = widget.segundosTranscurridos % 60;
    final tiempoStr =
        '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}';

    final nivelRecomendado = tasa >= 0.8 ? 'Medio' : 'Bajo';

    final ajuste = widget.ajustesDificultad.isNotEmpty
        ? widget.ajustesDificultad.first
        : null;
    final nivelSugerido = ajuste?['dificultad_sugerida']?.toString() ??
        widget.nivelDificultadRecomendado ??
        nivelRecomendado;
    final accionAjuste = ajuste?['accion']?.toString() ?? '';
    final dificultadActual =
        ajuste?['dificultad_actual']?.toString() ?? 'nivel actual';
    final muestras = (ajuste?['muestras'] as num?)?.toInt() ?? 0;
    final tasaAjuste = (ajuste?['tasa_aciertos'] as num?)?.toDouble() ?? tasa;
    final sugerenciaAplicable = widget.permitirAplicarSugerencia &&
        !isFamilyRoute &&
        ajuste?['aplicable'] == true &&
        _appliedLevel == null;
    final ajusteRegistrado =
        ajuste?['registrado'] == true || _appliedLevel != null;
    final solicitudAplicable = isFamilyRoute &&
        ajuste?['aplicable'] == true &&
        _requestStatus == null &&
        widget.sesionId != null;
    final ajusteTitle = ajuste == null
        ? 'Sin ajuste automatico'
        : accionAjuste == 'reducir'
            ? 'Reducir dificultad'
            : accionAjuste == 'mantener'
                ? 'Mantener dificultad'
                : 'Aumentar dificultad';
    final ajusteLabel = ajuste == null
        ? 'No se registro ajuste porque esta actividad aun no tiene historial suficiente, no cruzo 80% / 40%, o el plan ya esta en el limite de dificultad.'
        : ajusteRegistrado
            ? '$dificultadActual -> ${_appliedLevel ?? nivelSugerido} aplicado con ${(tasaAjuste * 100).toStringAsFixed(0)}% en $muestras resultados recientes.'
            : '$dificultadActual -> $nivelSugerido sugerido con ${(tasaAjuste * 100).toStringAsFixed(0)}% en $muestras resultados recientes.';

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Resumen de Sesión',
        leadingIcon: Icons.arrow_back,
        iconColor: _kPrimary,
        onLeadingPressed: () {
          if (context.canPop()) {
            context.pop();
          } else if (widget.ninoId != null) {
            context.go(isFamilyRoute
                ? '/familia/plan/${widget.ninoId}'
                : '/terapeuta/plan/${widget.ninoId}');
          } else {
            context.go(
                isFamilyRoute ? '/familia/dashboard' : '/terapeuta/dashboard');
          }
        },
        trailingWidget: IconButton(
          tooltip: 'Inicio',
          icon: const Icon(Icons.home_rounded, color: _kSubtext),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 96 + MediaQuery.of(context).padding.top,
          left: 24,
          right: 24,
          bottom: 48,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Encabezado ──────────────────────────────────────────────────
            const Text(
              'Sesión completada',
              style: TextStyle(color: _kSubtext, fontSize: 14),
            ),
            Text(
              widget.ninoNombre,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            const SizedBox(height: 32),
            if (widget.pendienteSync) ...[
              const BentoCard(
                backgroundColor: Color(0xFFFFF2CC),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cloud_off_outlined, color: Color(0xFF6B4300)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Guardado localmente. Se sincronizara automaticamente cuando vuelva la conexion.',
                        style: TextStyle(
                          color: Color(0xFF6B4300),
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Score principal ─────────────────────────────────────────────
            BentoCard(
              backgroundColor: _kSurface,
              child: Column(
                children: [
                  Text(
                    '${(tasa * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w900,
                      color: tasaColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tasa de Aciertos',
                    style: TextStyle(color: _kSubtext, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: tasa,
                      minHeight: 12,
                      backgroundColor: const Color(0xFFE9E1D8),
                      color: tasaColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Métricas ────────────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, metricConstraints) {
                final metricTiles = [
                  _MetricTile(
                      label: 'ACIERTOS',
                      value:
                          '${widget.totalAciertos} / ${widget.totalIntentos}'),
                  _MetricTile(label: 'DURACIÓN', value: tiempoStr),
                  _MetricTile(label: 'AYUDA', value: widget.nivelAyuda),
                ];

                if (metricConstraints.maxWidth < 520) {
                  return Column(
                    children: metricTiles
                        .map((tile) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: tile,
                            ))
                        .toList(),
                  );
                }

                return Row(
                  children: [
                    Expanded(child: metricTiles[0]),
                    const SizedBox(width: 16),
                    Expanded(child: metricTiles[1]),
                    const SizedBox(width: 16),
                    Expanded(child: metricTiles[2]),
                  ],
                );
              },
            ),
            if (widget.observaciones != null &&
                widget.observaciones!.isNotEmpty) ...[
              const SizedBox(height: 24),
              BentoCard(
                backgroundColor: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OBSERVACIONES',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _kSubtext,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(widget.observaciones!,
                        style: const TextStyle(color: _kText, height: 1.4)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Recomendación IA-01 ─────────────────────────────────────────
            BentoCard(
              backgroundColor: const Color(0xFF4A624D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AJUSTE AUTOMATICO',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFCFE9CF),
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ajusteTitle,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ajusteLabel,
                    style:
                        const TextStyle(color: Color(0xFFB3CDB4), fontSize: 14),
                  ),
                  if (sugerenciaAplicable) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _applying
                            ? null
                            : () => _aplicarSugerencia(
                                  ajuste: ajuste!,
                                  nivelSugerido: nivelSugerido,
                                  tasaAjuste: tasaAjuste,
                                  muestras: muestras,
                                ),
                        icon: const Icon(Icons.tune),
                        label: Text(
                            _applying ? 'Aplicando...' : 'Aplicar sugerencia'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAction,
                          foregroundColor: _kText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                  if (solicitudAplicable) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _requesting
                                ? null
                                : () =>
                                    setState(() => _requestStatus = 'omitida'),
                            icon: const Icon(Icons.close),
                            label: const Text('Mantener por ahora'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFFB3CDB4)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _requesting
                                ? null
                                : () => _solicitarAjuste(
                                      ajuste: ajuste!,
                                      nivelSugerido: nivelSugerido,
                                      tasaAjuste: tasaAjuste,
                                      muestras: muestras,
                                    ),
                            icon: const Icon(Icons.send_outlined),
                            label: Text(_requesting
                                ? 'Enviando...'
                                : 'Sí, solicitar cambio'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAction,
                              foregroundColor: _kText,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              textStyle:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_requestStatus != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _requestStatus == 'enviada'
                          ? 'Solicitud enviada. El terapeuta la revisara antes de cambiar la dificultad.'
                          : 'Se mantendra la dificultad actual por ahora.',
                      style: const TextStyle(color: Color(0xFFCFE9CF)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Acciones ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (widget.ninoId != null) {
                    ref.invalidate(planActivoProvider(widget.ninoId!));
                  }
                  widget.ninoId == null
                      ? context.go(isFamilyRoute
                          ? '/familia/dashboard'
                          : '/terapeuta/dashboard')
                      : context.go(isFamilyRoute
                          ? '/familia/plan/${widget.ninoId}'
                          : '/terapeuta/plan/${widget.ninoId}');
                },
                icon: const Icon(Icons.arrow_back),
                label: Text(widget.sesionNumero == null
                    ? 'Volver a la sesion'
                    : 'Volver a la sesion ${widget.sesionNumero}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAction,
                  foregroundColor: _kText,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _aplicarSugerencia({
    required Map<String, dynamic> ajuste,
    required String nivelSugerido,
    required double tasaAjuste,
    required int muestras,
  }) async {
    final planId = widget.planId;
    final actividadId = ajuste['actividad_id']?.toString();
    if (planId == null || actividadId == null || actividadId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontro el plan o la actividad para ajustar.'),
        ),
      );
      return;
    }

    setState(() => _applying = true);
    try {
      await ref.read(dashboardServiceProvider).actualizarDificultadActividad(
            planId: planId,
            actividadId: actividadId,
            nivelDificultad: nivelSugerido,
            origen: 'sugerencia_automatica',
            observacion: 'Aplicado desde resumen de sesion',
            tasaAciertos: tasaAjuste,
            muestras: muestras,
          );
      if (widget.ninoId != null) {
        ref.invalidate(planActivoProvider(widget.ninoId!));
      }
      if (!mounted) return;
      setState(() => _appliedLevel = nivelSugerido);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dificultad actualizada a $nivelSugerido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aplicar la sugerencia: $e')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _solicitarAjuste({
    required Map<String, dynamic> ajuste,
    required String nivelSugerido,
    required double tasaAjuste,
    required int muestras,
  }) async {
    final sesionId = widget.sesionId;
    final planId = widget.planId;
    final actividadId = ajuste['actividad_id']?.toString();
    final accion = ajuste['accion']?.toString();
    if (sesionId == null ||
        planId == null ||
        actividadId == null ||
        accion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('No se encontro la sesion para solicitar el ajuste.')),
      );
      return;
    }

    setState(() => _requesting = true);
    try {
      await ref.read(sesionServiceProvider).solicitarAjusteDificultad(
            sesionId: sesionId,
            planId: planId,
            actividadId: actividadId,
            accion: accion,
            dificultadActual:
                ajuste['dificultad_actual']?.toString() ?? 'Medio',
            dificultadSugerida: nivelSugerido,
            tasaAciertos: tasaAjuste,
            muestras: muestras,
            observacion: widget.observaciones,
          );
      if (!mounted) return;
      setState(() => _requestStatus = 'enviada');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud enviada al terapeuta.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la solicitud: $e')),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: const EdgeInsets.all(20),
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _kSubtext,
                letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: _kText)),
          ),
        ],
      ),
    );
  }
}
