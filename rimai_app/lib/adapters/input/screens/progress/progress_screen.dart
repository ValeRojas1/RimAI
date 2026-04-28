import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  final String ninoId;
  const ProgressScreen({super.key, required this.ninoId});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  String _selectedPeriod = 'Esta semana';
  String _selectedSkill = 'Atención Conjunta';
  bool _consentimientoActivo = true; // Simulado para IA-05

  @override
  Widget build(BuildContext context) {
    final metricasAsync = ref.watch(metricasProgresoFutureProvider(widget.ninoId));

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: "Progreso Clínico",
        leadingIcon: Icons.insights,
        iconColor: const Color(0xFF4A624D),
        trailingWidget: const CircleAvatar(
          radius: 20,
          backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=32'),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 3, // Progreso
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 1) context.go('/terapeuta/sesion');
          if (index == 2) context.go('/terapeuta/ia');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: "Inicio"),
          BottomNavItem(icon: Icons.spatial_audio_off, label: "Sesión"),
          BottomNavItem(icon: Icons.auto_awesome, label: "IA"),
          BottomNavItem(icon: Icons.insights, label: "Progreso"),
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
                 data: (metricas) => _buildKPIs(metricas),
                 loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF4A624D))),
                 error: (e, st) => Text("Error cargando métricas: $e"),
               ),
               const SizedBox(height: 24),
               _buildChartsGrid(),
             ],
           ),
         ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Análisis de Desempeño",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E1B16),
          ),
        ),
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
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4A624D)),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4A624D)),
              items: ['Esta semana', 'Este mes', 'Total'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) setState(() => _selectedPeriod = newValue);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKPIs(MetricasProgreso metricas) {
    // Determine colors
    Color getMerticColor(double val) {
      if (val >= 0.8) return const Color(0xFF22C55E); // Green
      if (val >= 0.5) return const Color(0xFFD97706); // Amber/Marron
      return const Color(0xFFBA1A1A); // Red
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final children = [
          _buildKpiCard("SESIONES", metricas.sesionesCompletadas.toString(), const Color(0xFF1E1B16)),
          _buildKpiCard("ACIERTOS", "${(metricas.tasaAciertos*100).toInt()}%", getMerticColor(metricas.tasaAciertos)),
          _buildKpiCard("ADHERENCIA", "${(metricas.adherencia*100).toInt()}%", getMerticColor(metricas.adherencia)),
        ];

        if (isMobile) {
          return Column(
            children: children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList(),
          );
        } else {
          return Row(
            children: children.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c))).toList(),
          );
        }
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
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF58423B), letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildChartsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
         if (constraints.maxWidth >= 1024) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildLineChartCard()),
                const SizedBox(width: 24),
                Expanded(child: _buildEmotionalChartCard()),
              ],
            );
         } else {
            return Column(
              children: [
                _buildLineChartCard(),
                const SizedBox(height: 24),
                _buildEmotionalChartCard(),
                const SizedBox(height: 24),
                _buildSkillsBreakdownCard(),
              ],
            );
         }
      },
    );
  }

  Widget _buildLineChartCard() {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: const [
                   Text("EVOLUCIÓN CLÍNICA", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF58423B), letterSpacing: 1)),
                   SizedBox(height: 4),
                   Text("Tasa de Aciertos por Sesión", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                 ],
               ),
               DropdownButton<String>(
                  value: _selectedSkill,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.filter_list, size: 16),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4A624D), fontSize: 14),
                  items: ['Atención Conjunta', 'Motricidad Fina'].map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) setState(() => _selectedSkill = newValue);
                  },
               ),
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
                  getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFDFC0B7).withOpacity(0.5), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text("S${value.toInt()+1}", style: const TextStyle(fontSize: 12, color: Color(0xFF58423B))),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 5,
                minY: 0,
                maxY: 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 0.5),
                      FlSpot(1, 0.6),
                      FlSpot(2, 0.65),
                      FlSpot(3, 0.8),
                      FlSpot(4, 0.85),
                      FlSpot(5, 0.9),
                    ],
                    isCurved: true,
                    color: const Color(0xFF4A624D),
                    barWidth: 4,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFB8D6B2).withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      )
    );
  }

  Widget _buildEmotionalChartCard() {
    return BentoCard(
      backgroundColor: const Color(0xFF4A624D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("MÓDULO IA-05", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Color(0xFFCFE9CF))),
              Switch(
                value: _consentimientoActivo,
                activeColor: const Color(0xFFB8D6B2),
                onChanged: (val) => setState(() => _consentimientoActivo = val),
              )
            ],
          ),
          const SizedBox(height: 8),
          const Text("Resumen Emocional", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          
          if (_consentimientoActivo) ...[
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceEvenly,
                  maxY: 10,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const titles = ['Fel', 'Neu', 'Tri', 'Eno', 'Sor', 'Mie'];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(titles[value.toInt()], style: const TextStyle(color: Colors.white70, fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 8, color: const Color(0xFFB8D6B2), width: 16, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 5, color: const Color(0xFFCFE9CF), width: 16, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 2, color: Colors.white38, width: 16, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 1, color: Colors.white38, width: 16, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 4, barRods: [BarChartRodData(toY: 4, color: Colors.white60, width: 16, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 5, barRods: [BarChartRodData(toY: 0, color: Colors.white38, width: 16, borderRadius: BorderRadius.circular(4))]),
                  ]
                )
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: const [
                 Icon(Icons.info_outline, size: 16, color: Color(0xFFB3CDB4)),
                 SizedBox(width: 8),
                 Expanded(child: Text("Este dato no constituye diagnóstico clínico.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFFB3CDB4)))),
              ],
            )
          ] else ...[
             Container(
                 padding: const EdgeInsets.all(24),
                 decoration: BoxDecoration(
                   color: Colors.white.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(12),
                 ),
                 child: const Center(
                   child: Text(
                     "Módulo inactivo. \nRequiere confirmación del tutor para recopilar e inferir métricas visuales.",
                     textAlign: TextAlign.center,
                     style: TextStyle(color: Color(0xFFCFE9CF), height: 1.5),
                   ),
                 ),
              )
          ]
        ],
      ),
    );
  }
  
  Widget _buildSkillsBreakdownCard() {
    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            const Text("DESGLOSE POR HABILIDAD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF58423B), letterSpacing: 1)),
            const SizedBox(height: 24),
            _buildSkillRow("Atención Conjunta", 0.9, "Hace 2 días", const Color(0xFF22C55E)),
            const SizedBox(height: 16),
            _buildSkillRow("Motricidad Fina", 0.6, "Ayer", const Color(0xFFD97706)),
            const SizedBox(height: 16),
            _buildSkillRow("Reconocimiento de Formas", 0.3, "Hace 1 semana", const Color(0xFFBA1A1A)),
         ],
      )
    );
  }

  Widget _buildSkillRow(String title, double progress, String dateStr, Color color) {
    return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E1B16))),
             Text("${(progress*100).toInt()}%", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
           ],
         ),
         const SizedBox(height: 8),
         ClipRRect(
           borderRadius: BorderRadius.circular(100),
           child: LinearProgressIndicator(
             value: progress,
             minHeight: 8,
             backgroundColor: const Color(0xFFE9E1D8),
             color: color,
           ),
         ),
         const SizedBox(height: 4),
         Text("Última sesión: $dateStr", style: const TextStyle(fontSize: 12, color: Color(0xFF8B716A))),
       ],
    );
  }
}
