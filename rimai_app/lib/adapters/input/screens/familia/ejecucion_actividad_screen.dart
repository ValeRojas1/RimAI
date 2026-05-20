import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../domain/entities/actividad_local.dart';
import '../../../../application/usecases/registrar_actividad_usecase.dart';
import '../../../../application/usecases/sync_offline_usecase.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

// PMV 3: Vista para los padres (Offline-first)
class EjecucionActividadScreen extends StatefulWidget {
  final RegistrarActividadUsecase registrarUsecase;
  final SyncOfflineUsecase syncUsecase;

  const EjecucionActividadScreen({
    super.key,
    required this.registrarUsecase,
    required this.syncUsecase,
  });

  @override
  State<EjecucionActividadScreen> createState() =>
      _EjecucionActividadScreenState();
}

class _EjecucionActividadScreenState extends State<EjecucionActividadScreen> {
  final TextEditingController _obsController = TextEditingController();
  int _tiempo = 300; // 5 minutos por defecto
  int _apoyo = 0; // Independiente
  bool _completada = true;
  List<String> _detonantes = [];

  void _guardarActividad() async {
    final actividad = ActividadLocal(
      patientId: 1, // Mock
      actividadId: "ACT-001",
      planId: 1,
      tiempoEmpleadoSegundos: _tiempo,
      nivelApoyoRequerido: _apoyo,
      observaciones: _obsController.text,
      detonantesPresentados: _detonantes,
      completada: _completada,
      timestampLocal: DateTime.now(),
    );

    await widget.registrarUsecase.execute(actividad);

    // Intentamos sincronizar inmediatamente (si falla, queda offline)
    await widget.syncUsecase.execute();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Actividad guardada correctamente.'),
          backgroundColor: Color(0xFF48BB78), // Success green
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7), // Background gris
      appBar: RimAITopBar(
        title: "Ejecución de Actividad",
        leadingIcon: Icons.arrow_back,
        onLeadingPressed: () => context.pop(),
        iconColor: const Color(0xFF1A365D), // Azul corporativo
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Registrar Sesión",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A365D)),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("¿Completó la actividad?",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SwitchListTile(
                      title: const Text("Sí, completada"),
                      value: _completada,
                      activeColor: const Color(0xFF48BB78),
                      onChanged: (val) => setState(() => _completada = val),
                    ),
                    const Divider(),
                    const Text("Nivel de Apoyo Requerido:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Slider(
                      value: _apoyo.toDouble(),
                      min: 0,
                      max: 3,
                      divisions: 3,
                      activeColor: const Color(0xFF1A365D),
                      label: [
                        "Independiente",
                        "Verbal",
                        "Visual",
                        "Físico"
                      ][_apoyo],
                      onChanged: (val) => setState(() => _apoyo = val.toInt()),
                    ),
                    const Divider(),
                    const Text("Observaciones Conductuales:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _obsController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText:
                            "Ej. Mostró interés pero se distrajo con ruido...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF48BB78), // Success
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text("Guardar Resultados",
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: _guardarActividad,
              ),
            )
          ],
        ),
      ),
    );
  }
}
