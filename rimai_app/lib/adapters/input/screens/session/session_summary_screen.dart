import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class SessionSummaryScreen extends ConsumerWidget {
  final int totalAciertos;
  final int totalIntentos;
  final int segundosTranscurridos;
  final String nivelAyuda;
  final String ninoNombre;
  final String? observaciones;
  final String? ninoId;
  final String? planId;
  final String? nivelDificultadRecomendado;
  final List<Map<String, dynamic>> ajustesDificultad;

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
    this.nivelDificultadRecomendado,
    this.ajustesDificultad = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasa = totalIntentos > 0 ? totalAciertos / totalIntentos : 0.0;
    final tasaColor = tasa >= 0.8
        ? const Color(0xFF22C55E)
        : tasa >= 0.5
            ? const Color(0xFFD97706)
            : const Color(0xFFBA1A1A);

    final minutos = (segundosTranscurridos / 60).floor();
    final segundos = segundosTranscurridos % 60;
    final tiempoStr =
        '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}';

    final nivelRecomendado = tasa >= 0.8 ? 'Medio' : 'Bajo';

    final ajuste =
        ajustesDificultad.isNotEmpty ? ajustesDificultad.first : null;
    final nivelSugerido = ajuste?['dificultad_sugerida']?.toString() ??
        nivelDificultadRecomendado ??
        nivelRecomendado;
    final accionAjuste = ajuste?['accion']?.toString() ?? '';
    final dificultadActual =
        ajuste?['dificultad_actual']?.toString() ?? 'nivel actual';
    final muestras = (ajuste?['muestras'] as num?)?.toInt() ?? 0;
    final tasaAjuste = (ajuste?['tasa_aciertos'] as num?)?.toDouble() ?? tasa;
    final ajusteTitle = ajuste == null
        ? 'Sin ajuste automatico'
        : accionAjuste == 'reducir'
            ? 'Reducir dificultad'
            : 'Aumentar dificultad';
    final ajusteLabel = ajuste == null
        ? 'Se requieren resultados previos o cruzar los umbrales 80% / 40%.'
        : '$dificultadActual -> $nivelSugerido registrado con ${(tasaAjuste * 100).toStringAsFixed(0)}% en $muestras resultados recientes.';

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Resumen de Sesión',
        leadingIcon: Icons.check_circle_outline,
        iconColor: _kPrimary,
        trailingWidget: IconButton(
          icon: const Icon(Icons.close, color: _kSubtext),
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
              ninoNombre,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            const SizedBox(height: 32),

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
                      value: '$totalAciertos / $totalIntentos'),
                  _MetricTile(label: 'DURACIÓN', value: tiempoStr),
                  _MetricTile(label: 'AYUDA', value: nivelAyuda),
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
            if (observaciones != null && observaciones!.isNotEmpty) ...[
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
                    Text(observaciones!,
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
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Acciones ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => ninoId == null
                    ? context.go('/terapeuta/dashboard')
                    : context.go('/terapeuta/plan/$ninoId'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Nueva actividad'),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/terapeuta/dashboard'),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Finalizar sesion'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kSubtext,
                  side: const BorderSide(color: Color(0xFFDFC0B7)),
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
