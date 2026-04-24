import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Modelos Mock ---

class PacientePerfil {
  final String id;
  final String nombre;
  final int edad;
  final List<String> intereses;
  final Map<String, List<String>> estimulosAversivos;
  final List<String> diagnosticos;

  PacientePerfil({
    required this.id,
    required this.nombre,
    required this.edad,
    required this.intereses,
    required this.estimulosAversivos,
    required this.diagnosticos,
  });

  PacientePerfil copyWith({
    String? nombre,
    int? edad,
    List<String>? intereses,
    Map<String, List<String>>? estimulosAversivos,
    List<String>? diagnosticos,
  }) {
    return PacientePerfil(
      id: id,
      nombre: nombre ?? this.nombre,
      edad: edad ?? this.edad,
      intereses: intereses ?? this.intereses,
      estimulosAversivos: estimulosAversivos ?? this.estimulosAversivos,
      diagnosticos: diagnosticos ?? this.diagnosticos,
    );
  }
}

class ResumenSesionData {
  final double cargaCognitiva;
  final String focoEstimado;
  final double nivelCalma;

  ResumenSesionData({
    required this.cargaCognitiva,
    required this.focoEstimado,
    required this.nivelCalma,
  });
}

class SessionStep {
  final String title;
  final String description;
  final String duration;
  final bool hasScanning;

  SessionStep({
    required this.title,
    required this.description,
    required this.duration,
    this.hasScanning = false,
  });
}

// --- Servicios Mock ---

class PerfilService {
  Future<PacientePerfil> obtenerPerfil(String ninoId) async {
    await Future.delayed(const Duration(seconds: 1)); // Simular red
    return PacientePerfil(
      id: ninoId,
      nombre: 'Lucas',
      edad: 7,
      intereses: ['Dinosaurios', 'Trenes', 'Lego', 'Manzana', 'Pelota ahulada'],
      estimulosAversivos: {
        'RUIDO': ['Licuadora', 'Gritos'],
        'COLORES': ['Rojo chillón'],
        'LUGARES': ['Multitudes'],
      },
      diagnosticos: [],
    );
  }

  Future<void> actualizarPerfil(PacientePerfil perfil) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<String> cargarDiagnostico(dynamic file) async {
    await Future.delayed(const Duration(seconds: 2));
    return 'diagnostico_tea_2023.pdf';
  }
}

class MotorAdaptativoService {
  Future<ResumenSesionData> obtenerResumenSesion(String ninoId) async {
    await Future.delayed(const Duration(seconds: 2));
    return ResumenSesionData(
      cargaCognitiva: 0.64,
      focoEstimado: '22 min',
      nivelCalma: 8.4,
    );
  }
}

class RecomendarActividadUseCase {
  Future<List<SessionStep>> ejecutar(String ninoId) async {
    await Future.delayed(const Duration(seconds: 2));
    return [
      SessionStep(
        title: 'Calibración Sensorial',
        description: 'Uso de luces suaves en tono verde para establecer calma basal.',
        duration: '5 MINUTOS',
        hasScanning: true,
      ),
      SessionStep(
        title: 'Atención Conjunta con Dinosaurios',
        description: 'Integrar intereses principales para fomentar el seguimiento visual.',
        duration: '15 MINUTOS',
      ),
      SessionStep(
        title: 'Cierre y Regulación',
        description: 'Transición suave con conteo regresivo y apoyo propioceptivo.',
        duration: '10 MINUTOS',
      ),
    ];
  }
}

class SesionService {
  Future<void> guardarObservacion(String sesionId, String texto) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

// --- Providers PMV2 PARTE 1 ---

final perfilServiceProvider = Provider((ref) => PerfilService());
final motorAdaptativoServiceProvider = Provider((ref) => MotorAdaptativoService());
final recomendarActividadUseCaseProvider = Provider((ref) => RecomendarActividadUseCase());
final sesionServiceProvider = Provider((ref) => SesionService());

final perfilPacienteProvider = FutureProvider.family<PacientePerfil, String>((ref, ninoId) {
  return ref.read(perfilServiceProvider).obtenerPerfil(ninoId);
});

final resumenSesionProvider = FutureProvider.family<ResumenSesionData, String>((ref, ninoId) {
  return ref.read(motorAdaptativoServiceProvider).obtenerResumenSesion(ninoId);
});

final planSesionProvider = FutureProvider.family<List<SessionStep>, String>((ref, ninoId) {
  return ref.read(recomendarActividadUseCaseProvider).ejecutar(ninoId);
});


// ============================================================================ //
// --- PMV2 PARTE 2: Modelos Mock ---
// ============================================================================ //

class MetricasProgreso {
  final int sesionesCompletadas;
  final double tasaAciertos;
  final double adherencia;
  
  MetricasProgreso({
    required this.sesionesCompletadas,
    required this.tasaAciertos,
    required this.adherencia,
  });
}

class RecomendacionClinica {
  final String id;
  final String actividad;
  final String justificacion;
  final double confianza;
  final DateTime fechaRespuesta;
  final String estado; // PENDIENTE, ACEPTADA, RECHAZADA, MODIFICADA
  final String? observacion;

  RecomendacionClinica({
    required this.id,
    required this.actividad,
    required this.justificacion,
    required this.confianza,
    required this.fechaRespuesta,
    required this.estado,
    this.observacion,
  });

  RecomendacionClinica copyWith({
    String? estado,
    String? observacion,
  }) {
    return RecomendacionClinica(
      id: id,
      actividad: actividad,
      justificacion: justificacion,
      confianza: confianza,
      fechaRespuesta: fechaRespuesta,
      estado: estado ?? this.estado,
      observacion: observacion ?? this.observacion,
    );
  }
}

// --- PMV2 PARTE 2: Servicios Mock ---

class AjustarDificultadUseCase {
  Future<int> ejecutar(bool acierto) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Simulated new difficulty logic
    return 1;
  }
}

class IndicadoresProgresoService {
  Future<MetricasProgreso> obtenerMetricas(String ninoId, String periodo) async {
    await Future.delayed(const Duration(seconds: 1));
    return MetricasProgreso(
      sesionesCompletadas: 12,
      tasaAciertos: 0.85,
      adherencia: 0.92,
    );
  }

  Future<List<double>> obtenerHistoriaAciertos(String ninoId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [0.5, 0.6, 0.65, 0.8, 0.85, 0.9];
  }
}

class RegistrarDecisionClinicaUseCase {
  Future<void> ejecutar(String recomendacionId, String accion, String observacion) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

// --- PMV2 PARTE 2: Providers ---

final ajustarDificultadProvider = Provider((ref) => AjustarDificultadUseCase());
final indicadoresProgresoProvider = Provider((ref) => IndicadoresProgresoService());
final registrarDecisionProvider = Provider((ref) => RegistrarDecisionClinicaUseCase());

final metricasProgresoFutureProvider = FutureProvider.family<MetricasProgreso, String>((ref, ninoId) {
  // we default to "Esta semana"
  return ref.read(indicadoresProgresoProvider).obtenerMetricas(ninoId, 'Esta semana');
});

// A dummy state notifier to manage the list of recommendations
class RecomendacionesNotifier extends StateNotifier<List<RecomendacionClinica>> {
  RecomendacionesNotifier() : super([]) {
    _loadMocks();
  }

  void _loadMocks() {
    state = [
      RecomendacionClinica(
        id: 'r1',
        actividad: 'Aumentar tiempo calistenia visual',
        justificacion: 'Foco estimado ha mejorado un +15% en las últimas 3 sesiones, sugiriendo capacidad para mantener umbral de atención prolongado.',
        confianza: 0.88,
        fechaRespuesta: DateTime.now(),
        estado: 'PENDIENTE',
      ),
      RecomendacionClinica(
        id: 'r2',
        actividad: 'Cambiar estímulo acústico a ruido rosa',
        justificacion: 'Reacciones de evitación registradas consistentemente en frecuencia 4K Hz. Ruido rosa pondera positivamente en perfil basal.',
        confianza: 0.92,
        fechaRespuesta: DateTime.now().subtract(const Duration(days: 2)),
        estado: 'ACEPTADA',
        observacion: 'Aplicado progresivamente.',
      ),
    ];
  }

  void updateEstado(String id, String nuevoEstado, String observacion) {
    state = state.map((r) {
      if (r.id == id) {
        return r.copyWith(estado: nuevoEstado, observacion: observacion);
      }
      return r;
    }).toList();
  }
}

final recomendacionesProvider = StateNotifierProvider<RecomendacionesNotifier, List<RecomendacionClinica>>((ref) {
  return RecomendacionesNotifier();
});
