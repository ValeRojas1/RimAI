import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';

// Mock de la bandeja del terapeuta con priorizacion visual (PMV 2)
class TherapistInboxScreen extends StatelessWidget {
  const TherapistInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Casos hardcodeados simulando el orden de IA de priorizacion (< 100ms backend)
    final casos = [
      {
        "nombre": "Lucas Mendoza",
        "edad": "5 años",
        "estado": "Requiere Plan",
        "scq": "16 (Alto Indicio)",
        "prioridad": "ALTA"
      },
      {
        "nombre": "Mateo Vargas",
        "edad": "4 años",
        "estado": "Evaluación pendiente",
        "scq": "12 (Moderado)",
        "prioridad": "MEDIA"
      },
      {
        "nombre": "Sofia Luna",
        "edad": "6 años",
        "estado": "En intervención",
        "scq": "6 (Bajo)",
        "prioridad": "BAJA"
      }
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7),
      appBar: RimAITopBar(
        title: "Bandeja de Pacientes",
        leadingIcon: Icons.menu,
        iconColor: const Color(0xFF1A365D),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 0, // Bandeja
        onTap: (index) {
          // Nav logic
        },
        items: [
          BottomNavItem(icon: Icons.inbox, label: "Pacientes"),
          BottomNavItem(icon: Icons.auto_awesome, label: "IA Support"),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Priorización Inteligente",
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A365D)),
            ),
            const SizedBox(height: 8),
            const Text(
                "Lista de casos ordenada por nivel de urgencia/indicio SCQ."),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: casos.length,
                itemBuilder: (context, index) {
                  final caso = casos[index];
                  Color prioColor;
                  if (caso["prioridad"] == "ALTA") {
                    prioColor = Colors.redAccent;
                  } else if (caso["prioridad"] == "MEDIA") {
                    prioColor = Colors.orangeAccent;
                  } else {
                    prioColor = const Color(0xFF48BB78);
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: prioColor,
                          width: caso["prioridad"] == "ALTA" ? 2 : 0),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(caso["nombre"]!,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF1A365D))),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text("Edad: ${caso["edad"]}"),
                          Text("Estado: ${caso["estado"]}"),
                          const SizedBox(height: 4),
                          Text("SCQ Result: ${caso["scq"]}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: prioColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: prioColor),
                            ),
                            child: Text(
                              caso["prioridad"]!,
                              style: TextStyle(
                                  color: prioColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (caso["prioridad"] == "ALTA") {
                          // Navegar al plan builder
                          context.push('/terapeuta/plan_builder',
                              extra: caso["nombre"]);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
