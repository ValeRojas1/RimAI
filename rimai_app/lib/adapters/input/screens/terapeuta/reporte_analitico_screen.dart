import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class ReporteAnaliticoScreen extends ConsumerStatefulWidget {
  final String ninoId;

  const ReporteAnaliticoScreen({super.key, required this.ninoId});

  @override
  ConsumerState<ReporteAnaliticoScreen> createState() =>
      _ReporteAnaliticoScreenState();
}

class _ReporteAnaliticoScreenState
    extends ConsumerState<ReporteAnaliticoScreen> {
  Map<String, dynamic>? _reporte;
  bool _loading = true;
  bool _exportingPdf = false;
  bool _exportingJson = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReporte();
  }

  Future<void> _loadReporte() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reporte = await ref
          .read(dashboardServiceProvider)
          .generarReporteTerapeutico(ninoId: widget.ninoId);
      if (!mounted) return;
      setState(() => _reporte = reporte);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reporte = _reporte;
    final nino = _map(reporte?['nino']);
    final title = nino['nombre']?.toString() ?? 'Reporte terapeutico';

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Reporte terapeutico',
        leadingIcon: Icons.arrow_back,
        iconColor: _kPrimary,
        onLeadingPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/terapeuta/dashboard');
          }
        },
        trailingWidget: IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh, color: _kSubtext),
          onPressed: _loading ? null : _loadReporte,
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 96 + MediaQuery.of(context).padding.top,
          left: 24,
          right: 24,
          bottom: 48,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : _error != null
                ? _ErrorState(error: _error!, onRetry: _loadReporte)
                : reporte == null
                    ? _ErrorState(
                        error: 'No se pudo generar el reporte.',
                        onRetry: _loadReporte,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _kText,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _periodLabel(_map(reporte['periodo'])),
                            style: const TextStyle(
                              color: _kSubtext,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildActions(reporte),
                          const SizedBox(height: 20),
                          _buildSummary(reporte),
                          const SizedBox(height: 20),
                          _buildTrends(reporte),
                          const SizedBox(height: 20),
                          _buildSkills(reporte),
                          const SizedBox(height: 20),
                          _buildSessions(reporte),
                          const SizedBox(height: 20),
                          _buildObservations(reporte),
                        ],
                      ),
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> reporte) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          ElevatedButton.icon(
            onPressed: _exportingPdf ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_exportingPdf ? 'Exportando...' : 'PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _exportingJson ? null : () => _exportJson(reporte),
            icon: const Icon(Icons.data_object),
            label: Text(_exportingJson ? 'Exportando...' : 'JSON'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ];
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: buttons[0]),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: buttons[1]),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: 12),
            Expanded(child: buttons[1]),
          ],
        );
      },
    );
  }

  Widget _buildSummary(Map<String, dynamic> reporte) {
    final resumen = _map(reporte['resumen']);
    final metrics = [
      ('SESIONES', _num(resumen['sesiones_completadas']).toInt().toString()),
      ('ACTIVIDADES', _num(resumen['actividades_registradas']).toInt().toString()),
      ('ACIERTOS', _percent(_num(resumen['tasa_aciertos_global']))),
      ('CUMPLIMIENTO', _percent(_num(resumen['cumplimiento_global']))),
    ];
    return BentoCard(
      backgroundColor: _kSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              children: metrics
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MetricTile(label: m.$1, value: m.$2),
                      ))
                  .toList(),
            );
          }
          return Row(
            children: metrics
                .map((m) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _MetricTile(label: m.$1, value: m.$2),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildTrends(Map<String, dynamic> reporte) {
    final tendencias = _map(reporte['tendencias']);
    final direction = tendencias['direccion']?.toString() ?? 'sin_datos';
    final variation = _num(tendencias['variacion_tasa_aciertos']);
    return BentoCard(
      backgroundColor: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: _kPrimary, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TENDENCIA',
                  style: TextStyle(
                    color: _kSubtext,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_capitalize(direction)} (${variation >= 0 ? '+' : ''}${_percent(variation)})',
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkills(Map<String, dynamic> reporte) {
    final rows = _list(reporte['progreso_por_habilidad']);
    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROGRESO POR HABILIDAD',
            style: TextStyle(
              color: _kSubtext,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text('Sin datos de progreso en el periodo.',
                style: TextStyle(color: _kSubtext))
          else
            ...rows.map((raw) {
              final row = _map(raw);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ProgressRow(
                  title: row['habilidad']?.toString() ?? 'Sin categoria',
                  percent: _num(row['tasa_aciertos']),
                  detail:
                      '${_num(row['actividades']).toInt()} actividades, ayuda ${_num(row['promedio_ayuda']).toStringAsFixed(1)}',
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSessions(Map<String, dynamic> reporte) {
    final rows = _list(reporte['sesiones']);
    return BentoCard(
      backgroundColor: _kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SESIONES',
            style: TextStyle(
              color: _kSubtext,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text('Sin sesiones completadas en el periodo.',
                style: TextStyle(color: _kSubtext))
          else
            ...rows.map((raw) {
              final row = _map(raw);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SessionTile(row: row),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildObservations(Map<String, dynamic> reporte) {
    final rows = _list(reporte['observaciones']);
    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OBSERVACIONES',
            style: TextStyle(
              color: _kSubtext,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text('Sin observaciones registradas en el periodo.',
                style: TextStyle(color: _kSubtext))
          else
            ...rows.take(8).map((raw) {
              final row = _map(raw);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${_shortDate(row['fecha'])} | ${row['actividad']}: ${row['observacion']}',
                  style: const TextStyle(color: _kText, height: 1.35),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final bytes = await ref
          .read(dashboardServiceProvider)
          .descargarReporteTerapeuticoPdf(ninoId: widget.ninoId);
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'reporte-terapeutico-${widget.ninoId}.pdf',
          mimeType: 'application/pdf',
        )
      ]);
    } catch (e) {
      _showError('No se pudo exportar el PDF: $e');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportJson(Map<String, dynamic> reporte) async {
    setState(() => _exportingJson = true);
    try {
      final content = const JsonEncoder.withIndent('  ').convert(reporte);
      await Share.shareXFiles([
        XFile.fromData(
          utf8.encode(content),
          name: 'reporte-terapeutico-${widget.ninoId}.json',
          mimeType: 'application/json',
        )
      ]);
    } catch (e) {
      _showError('No se pudo exportar el JSON: $e');
    } finally {
      if (mounted) setState(() => _exportingJson = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _kSubtext,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    color: _kText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String title;
  final double percent;
  final String detail;

  const _ProgressRow({
    required this.title,
    required this.percent,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = percent >= 0.8
        ? const Color(0xFF22C55E)
        : percent >= 0.5
            ? const Color(0xFFD97706)
            : const Color(0xFFBA1A1A);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _kText, fontWeight: FontWeight.w800)),
            ),
            Text(_percent(percent),
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: percent.clamp(0, 1).toDouble(),
            minHeight: 8,
            color: color,
            backgroundColor: const Color(0xFFE9E1D8),
          ),
        ),
        const SizedBox(height: 5),
        Text(detail, style: const TextStyle(color: _kSubtext, fontSize: 12)),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> row;

  const _SessionTile({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note, color: _kPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_shortDate(row['fecha']),
                    style: const TextStyle(
                        color: _kText, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${_num(row['total_aciertos']).toInt()}/${_num(row['total_intentos']).toInt()} aciertos, ayuda ${_num(row['promedio_ayuda']).toStringAsFixed(1)}',
                  style: const TextStyle(color: _kSubtext, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(_percent(_num(row['tasa_aciertos'])),
              style: const TextStyle(
                  color: _kPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: _kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error, style: const TextStyle(color: _kSubtext, height: 1.35)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  return {};
}

List<dynamic> _list(dynamic raw) => raw is List ? raw : const [];

double _num(dynamic raw) => raw is num ? raw.toDouble() : 0;

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
}

String _shortDate(dynamic raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '');
  if (date == null) return 'Sin fecha';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _periodLabel(Map<String, dynamic> periodo) {
  return '${_shortDate(periodo['inicio'])} - ${_shortDate(periodo['fin'])}';
}
