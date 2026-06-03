import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  final String ninoId;
  const ProgressScreen({super.key, required this.ninoId});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  String _selectedPeriod = 'Esta semana';
  String _selectedSkill = 'Todas';

  @override
  Widget build(BuildContext context) {
    final metricasAsync = ref.watch(metricasProgresoFutureProvider(
      (ninoId: widget.ninoId, periodo: _selectedPeriod),
    ));

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Progreso clinico',
        leadingIcon: Icons.arrow_back,
        iconColor: const Color(0xFF4A624D),
        onLeadingPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/terapeuta/nino/${widget.ninoId}');
          }
        },
        trailingWidget: const CircleAvatar(
          radius: 20,
          backgroundColor: Color(0xFFFAF2E9),
          child: Icon(Icons.person, color: Color(0xFF58423B)),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 3,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 1) context.go('/terapeuta/plan/${widget.ninoId}');
          if (index == 2) context.go('/terapeuta/ia/${widget.ninoId}');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Plan'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'Apoyo'),
          BottomNavItem(icon: Icons.insights, label: 'Progreso'),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            top: 96 + MediaQuery.of(context).padding.top,
            left: 24,
            right: 24,
            bottom: 120,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeriodSelector(),
              const SizedBox(height: 24),
              metricasAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4A624D)),
                ),
                error: (e, _) => Text('Error cargando metricas: $e'),
                data: (metricas) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKPIs(metricas),
                    const SizedBox(height: 24),
                    _buildChartsGrid(metricas),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Text(
            'Analisis de desempeno',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E1B16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFFDFC0B7)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPeriod,
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: Color(0xFF4A624D)),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF4A624D)),
              items: const ['Esta semana', 'Este mes', 'Total']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedPeriod = newValue;
                    _selectedSkill = 'Todas';
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Reporte',
          icon: const Icon(Icons.description_outlined,
              color: Color(0xFF4A624D)),
          onPressed: () => context.go('/terapeuta/reportes/${widget.ninoId}'),
        ),
      ],
    );
  }

  Widget _buildKPIs(MetricasProgreso metricas) {
    Color metricColor(double val) {
      if (val >= 0.8) return const Color(0xFF22C55E);
      if (val >= 0.5) return const Color(0xFFD97706);
      return const Color(0xFFBA1A1A);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = [
          _buildKpiCard('SESIONES', metricas.sesionesCompletadas.toString(),
              const Color(0xFF1E1B16)),
          _buildKpiCard('ACIERTOS', _percent(metricas.tasaAciertos),
              metricColor(metricas.tasaAciertos)),
          _buildKpiCard('ADHERENCIA', _percent(metricas.adherencia),
              metricColor(metricas.adherencia)),
          _buildKpiCard(
            'HABILIDADES',
            metricas.metricasPorHabilidad.length.toString(),
            const Color(0xFF4A624D),
          ),
        ];

        if (constraints.maxWidth < 720) {
          return Column(
            children: children
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: c,
                    ))
                .toList(),
          );
        }

        return Row(
          children: children
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: c,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildKpiCard(String label, String value, Color valueColor) {
    return BentoCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      backgroundColor: Colors.white,
      border: Border.all(color: const Color(0xFFE9E1D8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF58423B),
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsGrid(MetricasProgreso metricas) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1024) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildLineChartCard(metricas)),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _buildSkillsBreakdownCard(metricas)),
            ],
          );
        }
        return Column(
          children: [
            _buildLineChartCard(metricas),
            const SizedBox(height: 24),
            _buildSkillsBreakdownCard(metricas),
            const SizedBox(height: 24),
            _buildSessionsCard(metricas),
          ],
        );
      },
    );
  }

  Widget _buildLineChartCard(MetricasProgreso metricas) {
    final spots = <FlSpot>[];
    for (var i = 0; i < metricas.historiaAciertos.length; i++) {
      spots.add(FlSpot(i.toDouble(), metricas.historiaAciertos[i]));
    }
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EVOLUCION CLINICA',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF58423B),
                            letterSpacing: 1)),
                    SizedBox(height: 4),
                    Text('Tasa de aciertos por sesion',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _buildSkillDropdown(metricas)),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                      color: const Color(0xFFDFC0B7).withValues(alpha: 0.5),
                      strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('S${value.toInt() + 1}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF58423B))),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: spots.length > 1 ? (spots.length - 1).toDouble() : 1,
                minY: 0,
                maxY: 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF4A624D),
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFB8D6B2).withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillDropdown(MetricasProgreso metricas) {
    final skills = [
      'Todas',
      ...metricas.metricasPorHabilidad.map((m) => m.habilidad),
    ];
    final value = skills.contains(_selectedSkill) ? _selectedSkill : 'Todas';
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        icon: const Icon(Icons.filter_list, size: 16),
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF4A624D),
            fontSize: 14),
        isExpanded: false,
        items: skills
            .map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (newValue) {
          if (newValue != null) setState(() => _selectedSkill = newValue);
        },
      ),
    );
  }

  Widget _buildSkillsBreakdownCard(MetricasProgreso metricas) {
    final rows = _selectedSkill == 'Todas'
        ? metricas.metricasPorHabilidad
        : metricas.metricasPorHabilidad
            .where((item) => item.habilidad == _selectedSkill)
            .toList();

    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DESGLOSE POR HABILIDAD',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF58423B),
                  letterSpacing: 1)),
          const SizedBox(height: 18),
          if (rows.isEmpty)
            const Text('Aun no hay actividades registradas en este periodo.',
                style: TextStyle(color: Color(0xFF58423B)))
          else
            ...rows.map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildSkillRow(row),
                )),
          if (metricas.observacionesRecientes.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Color(0xFFE9E1D8)),
            const SizedBox(height: 12),
            const Text('OBSERVACIONES RECIENTES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF58423B),
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            ...metricas.observacionesRecientes.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${item.actividad}: ${item.observacion}',
                      style: const TextStyle(
                          color: Color(0xFF1E1B16), height: 1.35),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkillRow(MetricaHabilidadProgreso row) {
    final color = row.tasaAciertos >= 0.8
        ? const Color(0xFF22C55E)
        : row.tasaAciertos >= 0.5
            ? const Color(0xFFD97706)
            : const Color(0xFFBA1A1A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(row.habilidad,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1E1B16))),
            ),
            Text(_percent(row.tasaAciertos),
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: row.tasaAciertos.clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: const Color(0xFFE9E1D8),
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${row.actividades} actividades, ${row.sesiones} sesiones, ayuda ${row.promedioAyuda.toStringAsFixed(1)}, ${_minutes(row.promedioTiempo)} prom.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF8B716A)),
        ),
      ],
    );
  }

  Widget _buildSessionsCard(MetricasProgreso metricas) {
    final rows = metricas.sesiones.where((session) {
      if (_selectedSkill == 'Todas') return true;
      return session.habilidades.any((h) => h.habilidad == _selectedSkill);
    }).toList();

    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SESIONES DEL PERIODO',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF58423B),
                  letterSpacing: 1)),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            const Text('Sin sesiones completadas para este filtro.',
                style: TextStyle(color: Color(0xFF58423B)))
          else
            ...rows.map((session) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SessionRow(session: session),
                )),
        ],
      ),
    );
  }

  String _percent(double value) => '${(value * 100).round()}%';

  String _minutes(double seconds) {
    if (seconds <= 0) return '0 min';
    return '${(seconds / 60).toStringAsFixed(1)} min';
  }
}

class _SessionRow extends StatelessWidget {
  final SesionProgreso session;

  const _SessionRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final fecha = session.fecha;
    final fechaTexto = fecha == null
        ? 'Sin fecha'
        : '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFB8D6B2),
            foregroundColor: const Color(0xFF1E1B16),
            child: Text(session.sesionNumero.toString()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sesion $fechaTexto',
                    style: const TextStyle(
                        color: Color(0xFF1E1B16),
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${session.totalAciertos}/${session.totalIntentos} aciertos, ayuda ${session.promedioAyuda.toStringAsFixed(1)}, cumplimiento ${(session.cumplimiento * 100).round()}%',
                  style: const TextStyle(
                      color: Color(0xFF58423B), fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${(session.tasaAciertos * 100).round()}%',
            style: const TextStyle(
                color: Color(0xFF4A624D),
                fontSize: 18,
                fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
