import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../domain/entities/scq_result.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

// Este form es un mock para mostrar la interaccion,
// idealmente las preguntas vienen del backend o constantes locales
class SCQFormScreen extends StatefulWidget {
  final int patientId;

  const SCQFormScreen({super.key, required this.patientId});

  @override
  State<SCQFormScreen> createState() => _SCQFormScreenState();
}

class _SCQFormScreenState extends State<SCQFormScreen> {
  final List<int> _respuestas = List.filled(40, 0); // 40 items del SCQ
  bool _aceptoDisclaimer = false;

  void _submit() {
    if (!_aceptoDisclaimer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Debe aceptar la advertencia legal RNF-10 para continuar')),
      );
      return;
    }

    // Mock total para redirigir a resultados
    int total = _respuestas.reduce((a, b) => a + b);
    String nivel = "Bajo";
    if (total >= 15)
      nivel = "Alto";
    else if (total >= 11) nivel = "Moderado";

    // Ir a la vista de resultados pasando el mock (en produccion llamaria al SubmitSCQUsecase)
    SCQResult result = SCQResult(puntajeTotal: total, nivelIndicio: nivel);
    context.push('/padre/scq/resultados', extra: result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7), // Background gris
      appBar: RimAITopBar(
        title: "Cuestionario SCQ",
        leadingIcon: Icons.arrow_back,
        onLeadingPressed: () => context.pop(),
        iconColor: const Color(0xFF1A365D), // Primary blue
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Evaluación Inicial de Comunicación Social (SCQ)",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A365D)),
              ),
              const SizedBox(height: 16),
              const Text(
                  "Por favor, responda las siguientes preguntas sobre el comportamiento de su hijo/a. Seleccione SI (1) o NO (0)."),
              const SizedBox(height: 24),
              // Render mock questions
              ...List.generate(5, (index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text("Pregunta ${index + 1} del SCQ..."),
                    trailing: Switch(
                      value: _respuestas[index] == 1,
                      activeColor: const Color(0xFF48BB78), // Success Green
                      onChanged: (val) {
                        setState(() {
                          _respuestas[index] = val ? 1 : 0;
                        });
                      },
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.redAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      "ADVERTENCIA (RNF-10): Los resultados de este cuestionario y las evaluaciones realizadas por RimAI no constituyen un diagnóstico clínico médico definitivo. Son herramientas de apoyo indicativas.",
                      style: TextStyle(color: Colors.black87, fontSize: 13),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _aceptoDisclaimer,
                          activeColor: const Color(0xFF48BB78),
                          onChanged: (val) =>
                              setState(() => _aceptoDisclaimer = val ?? false),
                        ),
                        const Expanded(
                            child: Text(
                                "He leído, entiendo y acepto la advertencia legal.",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A365D), // Primary blue
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _submit,
                  child: const Text("Enviar Evaluación",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
