import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../domain/entities/scq_result.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

class SCQResultScreen extends StatelessWidget {
  final SCQResult result;

  const SCQResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;

    if (result.nivelIndicio == 'Alto') {
      statusColor = Colors.redAccent;
      statusIcon = Icons.warning_amber_rounded;
    } else if (result.nivelIndicio == 'Moderado') {
      statusColor = Colors.orangeAccent;
      statusIcon = Icons.info_outline;
    } else {
      statusColor = const Color(0xFF48BB78); // Success green
      statusIcon = Icons.check_circle_outline;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7), // Background gris
      appBar: RimAITopBar(
        title: "Resultados SCQ",
        leadingIcon: Icons.home,
        onLeadingPressed: () => context.go('/padre/dashboard'),
        iconColor: const Color(0xFF1A365D), // Primary blue
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(statusIcon, size: 80, color: statusColor),
            const SizedBox(height: 24),
            Text(
              "Nivel de Indicio: ${result.nivelIndicio}",
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: statusColor),
            ),
            const SizedBox(height: 8),
            Text(
              "Puntaje Total Obtenido: ${result.puntajeTotal}",
              style: const TextStyle(fontSize: 18, color: Colors.black54),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text(
                "Importante: La información ha sido enviada al terapeuta asignado, quien priorizará el caso y se pondrá en contacto pronto para la planificación terapéutica.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF1A365D), fontSize: 15),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A365D),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => context.go('/padre/dashboard'),
                child: const Text("Volver al Inicio",
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
