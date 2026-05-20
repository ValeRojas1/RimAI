import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../domain/entities/reporte.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

class ReporteAnaliticoScreen extends StatelessWidget {
  final ReporteAnalitico reporte;

  const ReporteAnaliticoScreen({super.key, required this.reporte});

  @override
  Widget build(BuildContext context) {
    bool isBajaAdherencia = reporte.tasaAdherenciaGlobal < 0.7; // < 70%

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7),
      appBar: RimAITopBar(
        title: "Reporte Analítico",
        leadingIcon: Icons.arrow_back,
        onLeadingPressed: () => context.pop(),
        iconColor: const Color(0xFF1A365D),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Rendimiento Terapéutico",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A365D))),
            const SizedBox(height: 16),
            if (isBajaAdherencia)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  border: Border.all(color: Colors.redAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "ALERTA: Baja Adherencia detectada (${(reporte.tasaAdherenciaGlobal * 100).toStringAsFixed(1)}%). Requiere intervención inmediata del terapeuta.",
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text("Tasa Global de Adherencia"),
                    const SizedBox(height: 8),
                    Text(
                      "${(reporte.tasaAdherenciaGlobal * 100).toStringAsFixed(1)}%",
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isBajaAdherencia
                              ? Colors.redAccent
                              : const Color(0xFF48BB78)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text("Métricas por Actividad",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A365D))),
            const SizedBox(height: 8),
            ...reporte.metricasPorActividad.map((m) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text("Actividad: ${m.actividadId}"),
                    subtitle: Text(
                        "Completitud: ${(m.tasaCompletitud * 100).toStringAsFixed(1)}% | Apoyo Prom: ${m.promedioApoyo.toStringAsFixed(1)}"),
                    trailing:
                        const Icon(Icons.bar_chart, color: Color(0xFF1A365D)),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
