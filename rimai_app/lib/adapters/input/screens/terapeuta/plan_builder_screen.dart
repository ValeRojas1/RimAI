import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

// PMV2: Vista de sugerencias de Plan (Borrador -> Validado)
class PlanBuilderScreen extends StatefulWidget {
  final String patientName;
  const PlanBuilderScreen({super.key, required this.patientName});

  @override
  State<PlanBuilderScreen> createState() => _PlanBuilderScreenState();
}

class _PlanBuilderScreenState extends State<PlanBuilderScreen> {
  // Mock de sugerencias provenientes de GenerarPlanSugeridoUseCase
  final List<Map<String, String>> sugerencias = [
    {
      "actividad": "Calibración con luces tenues (Silenciosa)",
      "justificacion": "Adaptado por aversión detectada a ruidos fuertes."
    },
    {
      "actividad": "Juego de turnos estructurado",
      "justificacion":
          "Actividad estándar para desarrollo de comunicación social."
    }
  ];

  void _validarPlan() {
    // Simulacion de validacion
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Plan Terapéutico VALIDADO y asignado exitosamente.'),
        backgroundColor: Color(0xFF48BB78),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7),
      appBar: RimAITopBar(
        title: "Plan Terapéutico",
        leadingIcon: Icons.arrow_back,
        onLeadingPressed: () => context.pop(),
        iconColor: const Color(0xFF1A365D),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Estado actual: BORRADOR.\nPaciente: ${widget.patientName}\nEl motor ha generado estas sugerencias basado en el SCQ y el perfil sensorial. Requiere validación del terapeuta.",
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text("Sugerencias de Actividades:",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A365D))),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: sugerencias.length,
                itemBuilder: (context, index) {
                  final sug = sugerencias[index];
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sug["actividad"]!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text("Justificación IA: ${sug["justificacion"]}",
                              style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black54)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF48BB78), // Verde esmeralda (Success)
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _validarPlan,
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: const Text("Validar y Asignar Plan",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
