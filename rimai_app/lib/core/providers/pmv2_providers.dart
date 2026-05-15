import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rimai_app/core/providers/dashboard_providers.dart';

Map<String, dynamic> _toMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
  throw Exception('Respuesta inesperada del servidor');
}

class PacientePerfil {
  final String id;
  final String nombre;
  final int edad;
  final String? diagnostico;
  final String nivelCognitivo;
  final Map<String, dynamic> perfilSensorial;
  final List<String> objetivosIntervencion;
  final List<String> intereses;
  final Map<String, List<String>> estimulosAversivos;
  final List<String> diagnosticos;
  final String? planActivoId;
  final String estadoClinico;

  PacientePerfil({
    required this.id,
    required this.nombre,
    required this.edad,
    this.diagnostico,
    required this.nivelCognitivo,
    required this.perfilSensorial,
    required this.objetivosIntervencion,
    required this.intereses,
    required this.estimulosAversivos,
    required this.diagnosticos,
    this.planActivoId,
    this.estadoClinico = 'pendiente_asignacion',
  });

  factory PacientePerfil.fromJson(dynamic raw) {
    final j = _toMap(raw);
    final aversivosRaw = j['estimulos_aversivos'];
    final aversivos = <String, List<String>>{};
    if (aversivosRaw is Map) {
      aversivosRaw.forEach((key, value) {
        aversivos[key.toString()] = value is List
            ? value.map((e) => e.toString()).toList()
            : <String>[];
      });
    }

    final documento = j['documento_diagnostico']?.toString();
    return PacientePerfil(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      edad: (j['edad'] as num?)?.toInt() ?? 0,
      diagnostico: j['diagnostico']?.toString(),
      nivelCognitivo: j['nivel_cognitivo']?.toString() ?? 'Medio',
      perfilSensorial: j['perfil_sensorial'] is Map
          ? (j['perfil_sensorial'] as Map).cast<String, dynamic>()
          : {},
      objetivosIntervencion: j['objetivos_intervencion'] is List
          ? (j['objetivos_intervencion'] as List)
              .map((e) => e.toString())
              .toList()
          : [],
      intereses: j['intereses'] is List
          ? (j['intereses'] as List).map((e) => e.toString()).toList()
          : [],
      estimulosAversivos: aversivos,
      diagnosticos: documento == null || documento.isEmpty ? [] : [documento],
      planActivoId: j['plan_activo_id']?.toString(),
      estadoClinico: j['estado_clinico']?.toString() ?? 'pendiente_asignacion',
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

  factory ResumenSesionData.fromJson(Map<String, dynamic> j) {
    return ResumenSesionData(
      cargaCognitiva: (j['carga_cognitiva'] as num?)?.toDouble() ?? 0.5,
      focoEstimado: j['foco_estimado']?.toString() ?? '15 min',
      nivelCalma: (j['nivel_calma'] as num?)?.toDouble() ?? 7,
    );
  }
}

class SessionStep {
  final String id;
  final String title;
  final String description;
  final String duration;
  final bool hasScanning;

  SessionStep({
    required this.id,
    required this.title,
    required this.description,
    required this.duration,
    this.hasScanning = false,
  });

  factory SessionStep.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return SessionStep(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      duration: j['duration']?.toString() ?? '',
      hasScanning: j['has_scanning'] == true,
    );
  }
}

class NivelInicialData {
  final String nivelRecomendado;
  final double confianza;
  final bool fallback;
  final String? mensaje;

  NivelInicialData({
    required this.nivelRecomendado,
    required this.confianza,
    required this.fallback,
    this.mensaje,
  });

  factory NivelInicialData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return NivelInicialData(
      nivelRecomendado: j['nivel_recomendado']?.toString() ?? 'Medio',
      confianza: (j['confianza'] as num?)?.toDouble() ?? 0,
      fallback: j['fallback'] == true,
      mensaje: j['mensaje']?.toString(),
    );
  }
}

class IAAssistantData {
  final String ninoId;
  final String ninoNombre;
  final ResumenSesionData analisis;
  final List<RecomendacionClinica> recomendaciones;
  final List<SessionStep> planSesion;

  IAAssistantData({
    required this.ninoId,
    required this.ninoNombre,
    required this.analisis,
    required this.recomendaciones,
    required this.planSesion,
  });

  factory IAAssistantData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return IAAssistantData(
      ninoId: j['nino_id']?.toString() ?? '',
      ninoNombre: j['nino_nombre']?.toString() ?? 'Paciente',
      analisis: ResumenSesionData.fromJson(
          (j['analisis_cognitivo'] as Map?)?.cast<String, dynamic>() ?? {}),
      recomendaciones: j['recomendaciones'] is List
          ? (j['recomendaciones'] as List)
              .map((r) => RecomendacionClinica.fromJson(r))
              .toList()
          : [],
      planSesion: j['plan_sesion'] is List
          ? (j['plan_sesion'] as List)
              .map((s) => SessionStep.fromJson(s))
              .toList()
          : [],
    );
  }
}

class MetricasProgreso {
  final int sesionesCompletadas;
  final double tasaAciertos;
  final double adherencia;
  final List<double> historiaAciertos;

  MetricasProgreso({
    required this.sesionesCompletadas,
    required this.tasaAciertos,
    required this.adherencia,
    required this.historiaAciertos,
  });

  factory MetricasProgreso.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return MetricasProgreso(
      sesionesCompletadas: (j['sesiones_completadas'] as num?)?.toInt() ?? 0,
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble() ?? 0,
      adherencia: (j['adherencia'] as num?)?.toDouble() ?? 0,
      historiaAciertos: j['historia_aciertos'] is List
          ? (j['historia_aciertos'] as List)
              .map((e) => (e as num).toDouble())
              .toList()
          : [0],
    );
  }
}

class RecomendacionClinica {
  final String id;
  final String actividad;
  final String justificacion;
  final double confianza;
  final DateTime fechaRespuesta;
  final String estado;
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

  factory RecomendacionClinica.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return RecomendacionClinica(
      id: j['id']?.toString() ?? '',
      actividad: j['actividad']?.toString() ?? '',
      justificacion: j['justificacion']?.toString() ?? '',
      confianza: (j['confianza'] as num?)?.toDouble() ?? 0,
      fechaRespuesta:
          DateTime.tryParse(j['fecha_respuesta']?.toString() ?? '') ??
              DateTime.now(),
      estado: j['estado']?.toString() ?? 'PENDIENTE',
      observacion: j['observacion']?.toString(),
    );
  }

  RecomendacionClinica copyWith({String? estado, String? observacion}) {
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

class PerfilService {
  PerfilService(this._dio);
  final Dio _dio;

  Future<PacientePerfil> obtenerPerfil(String ninoId) async {
    final response = await _dio.get('/api/ninos/$ninoId');
    return PacientePerfil.fromJson(response.data);
  }

  Future<void> actualizarPerfil(PacientePerfil perfil) async {}

  Future<String> cargarDiagnostico(dynamic file) async {
    return file?.toString().split(RegExp(r'[\\/]')).last ?? 'diagnostico.pdf';
  }
}

class IAService {
  IAService(this._dio);
  final Dio _dio;

  Future<IAAssistantData> obtenerAsistente(String ninoId) async {
    final response = await _dio.get('/api/ia/asistente/$ninoId');
    return IAAssistantData.fromJson(response.data);
  }

  Future<NivelInicialData> estimarNivelInicial(
      String ninoId, String actividadId) async {
    final response = await _dio.post('/api/ia/nivel-inicial', data: {
      'nino_id': ninoId,
      'actividad_id': actividadId,
    });
    return NivelInicialData.fromJson(response.data);
  }

  Future<void> registrarDecision(
      String recomendacionId, String accion, String observacion,
      {String? ninoId}) async {
    await _dio.post('/api/ia/decision-clinica', data: {
      'recomendacion_id': recomendacionId,
      'accion': accion,
      'observacion': observacion,
      'nino_id': ninoId,
    });
  }
}

class SesionService {
  SesionService(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> guardarResultadoActividad({
    required String ninoId,
    required String planId,
    required String actividadId,
    required int aciertos,
    required int intentos,
    required int segundos,
    required String nivelAyuda,
    required String nivelDificultadUsado,
    String? observaciones,
  }) async {
    final response = await _dio.post('/api/sesiones', data: {
      'nino_id': ninoId,
      'plan_id': planId,
      'resultados': [
        {
          'actividad_id': actividadId,
          'aciertos': aciertos,
          'repeticiones': intentos,
          'tiempo_respuesta': segundos.toDouble(),
          'nivel_ayuda_requerido': {
                'Ninguna': 0,
                'Verbal': 1,
                'Fisica': 2,
                'Física': 2
              }[nivelAyuda] ??
              0,
          'nivel_dificultad_usado': nivelDificultadUsado,
          'observaciones': observaciones,
        }
      ],
    });
    return (response.data as Map).cast<String, dynamic>();
  }

  Future<void> guardarObservacion(String sesionId, String texto) async {}
}

class IndicadoresProgresoService {
  IndicadoresProgresoService(this._dio);
  final Dio _dio;

  Future<MetricasProgreso> obtenerMetricas(
      String ninoId, String periodo) async {
    final response = await _dio.get('/api/ninos/$ninoId/progreso',
        queryParameters: {'periodo': periodo});
    return MetricasProgreso.fromJson(response.data);
  }
}

class AjustarDificultadUseCase {
  Future<int> ejecutar(bool acierto) async {
    return acierto ? 2 : 1;
  }
}

final perfilServiceProvider =
    Provider((ref) => PerfilService(ref.read(dioProvider)));
final iaServiceProvider = Provider((ref) => IAService(ref.read(dioProvider)));
final sesionServiceProvider =
    Provider((ref) => SesionService(ref.read(dioProvider)));
final indicadoresProgresoProvider =
    Provider((ref) => IndicadoresProgresoService(ref.read(dioProvider)));
final ajustarDificultadProvider = Provider((ref) => AjustarDificultadUseCase());

final perfilPacienteProvider =
    FutureProvider.family<PacientePerfil, String>((ref, ninoId) {
  return ref.read(perfilServiceProvider).obtenerPerfil(ninoId);
});

final iaAssistantProvider =
    FutureProvider.family<IAAssistantData, String>((ref, ninoId) {
  return ref.read(iaServiceProvider).obtenerAsistente(ninoId);
});

final resumenSesionProvider =
    FutureProvider.family<ResumenSesionData, String>((ref, ninoId) async {
  final data = await ref.read(iaServiceProvider).obtenerAsistente(ninoId);
  return data.analisis;
});

final planSesionProvider =
    FutureProvider.family<List<SessionStep>, String>((ref, ninoId) async {
  final data = await ref.read(iaServiceProvider).obtenerAsistente(ninoId);
  return data.planSesion;
});

final nivelInicialProvider = FutureProvider.family<NivelInicialData,
    ({String ninoId, String actividadId})>((ref, args) {
  return ref
      .read(iaServiceProvider)
      .estimarNivelInicial(args.ninoId, args.actividadId);
});

final metricasProgresoFutureProvider =
    FutureProvider.family<MetricasProgreso, String>((ref, ninoId) {
  return ref
      .read(indicadoresProgresoProvider)
      .obtenerMetricas(ninoId, 'Esta semana');
});

class RegistrarDecisionClinicaUseCase {
  RegistrarDecisionClinicaUseCase(this._service);
  final IAService _service;

  Future<void> ejecutar(
      String recomendacionId, String accion, String observacion,
      {String? ninoId}) {
    return _service.registrarDecision(recomendacionId, accion, observacion,
        ninoId: ninoId);
  }
}

final registrarDecisionProvider = Provider(
    (ref) => RegistrarDecisionClinicaUseCase(ref.read(iaServiceProvider)));

class RecomendacionesNotifier
    extends StateNotifier<List<RecomendacionClinica>> {
  RecomendacionesNotifier() : super([]);

  void setRecomendaciones(List<RecomendacionClinica> recomendaciones) {
    state = recomendaciones;
  }

  void updateEstado(String id, String nuevoEstado, String observacion) {
    state = state
        .map((r) => r.id == id
            ? r.copyWith(estado: nuevoEstado, observacion: observacion)
            : r)
        .toList();
  }
}

final recomendacionesProvider =
    StateNotifierProvider<RecomendacionesNotifier, List<RecomendacionClinica>>(
        (ref) {
  return RecomendacionesNotifier();
});
