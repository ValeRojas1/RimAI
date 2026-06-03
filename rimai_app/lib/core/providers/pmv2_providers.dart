import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:rimai_app/adapters/output/sqlite_db_repository.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/domain/entities/actividad_local.dart';

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
  final List<String> rutinasRegulacion;
  final Map<String, dynamic> documentosClinicos;
  final String? medicacionActual;
  final String? planActivoId;
  final String estadoClinico;
  final String? planEstado;
  final int? nivelTeaValidado;
  final bool perfilValidado;
  final bool requiereScq;
  final bool scqCompletado;
  final bool scqAutorizadoEnvio;
  final bool tieneEvidenciaClinica;
  final int? scqPuntaje;
  final String? scqNivel;

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
    this.rutinasRegulacion = const [],
    this.documentosClinicos = const {},
    this.medicacionActual,
    this.planActivoId,
    this.estadoClinico = 'pendiente_asignacion',
    this.planEstado,
    this.nivelTeaValidado,
    this.perfilValidado = false,
    this.requiereScq = false,
    this.scqCompletado = false,
    this.scqAutorizadoEnvio = false,
    this.tieneEvidenciaClinica = false,
    this.scqPuntaje,
    this.scqNivel,
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
    final docs = j['documentos_clinicos'] is Map
        ? (j['documentos_clinicos'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
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
      rutinasRegulacion: j['rutinas_regulacion'] is List
          ? (j['rutinas_regulacion'] as List).map((e) => e.toString()).toList()
          : [],
      documentosClinicos: docs,
      medicacionActual: j['medicacion_actual']?.toString(),
      planActivoId: j['plan_activo_id']?.toString(),
      estadoClinico: j['estado_clinico']?.toString() ?? 'pendiente_asignacion',
      planEstado: j['plan_estado']?.toString(),
      nivelTeaValidado: (j['nivel_tea_validado'] as num?)?.toInt(),
      perfilValidado: j['perfil_validado'] == true,
      requiereScq: j['requiere_scq'] == true,
      scqCompletado: j['scq_completado'] == true,
      scqAutorizadoEnvio: j['scq_autorizado_envio'] == true,
      tieneEvidenciaClinica: j['tiene_evidencia_clinica'] == true ||
          (docs.isNotEmpty ||
              (j['diagnostico']?.toString().trim().isNotEmpty ?? false) ||
              (j['medicacion_actual']?.toString().trim().isNotEmpty ?? false)),
      scqPuntaje: (j['scq_puntaje'] as num?)?.toInt(),
      scqNivel: j['scq_nivel']?.toString(),
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

class MetricaHabilidadProgreso {
  final String habilidad;
  final int sesiones;
  final int actividades;
  final double tasaAciertos;
  final double promedioTiempo;
  final double promedioAyuda;
  final double cumplimiento;

  MetricaHabilidadProgreso({
    required this.habilidad,
    required this.sesiones,
    required this.actividades,
    required this.tasaAciertos,
    required this.promedioTiempo,
    required this.promedioAyuda,
    required this.cumplimiento,
  });

  factory MetricaHabilidadProgreso.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return MetricaHabilidadProgreso(
      habilidad: j['habilidad']?.toString() ?? 'Sin categoria',
      sesiones: (j['sesiones'] as num?)?.toInt() ?? 0,
      actividades: (j['actividades'] as num?)?.toInt() ?? 0,
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble() ?? 0,
      promedioTiempo: (j['promedio_tiempo'] as num?)?.toDouble() ?? 0,
      promedioAyuda: (j['promedio_ayuda'] as num?)?.toDouble() ?? 0,
      cumplimiento: (j['cumplimiento'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SesionProgreso {
  final String sesionId;
  final int sesionNumero;
  final String planId;
  final DateTime? fecha;
  final double tasaAciertos;
  final int totalAciertos;
  final int totalIntentos;
  final double promedioTiempo;
  final double promedioAyuda;
  final double cumplimiento;
  final List<MetricaHabilidadProgreso> habilidades;

  SesionProgreso({
    required this.sesionId,
    required this.sesionNumero,
    required this.planId,
    this.fecha,
    required this.tasaAciertos,
    required this.totalAciertos,
    required this.totalIntentos,
    required this.promedioTiempo,
    required this.promedioAyuda,
    required this.cumplimiento,
    required this.habilidades,
  });

  factory SesionProgreso.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return SesionProgreso(
      sesionId: j['sesion_id']?.toString() ?? '',
      sesionNumero: (j['sesion_numero'] as num?)?.toInt() ?? 0,
      planId: j['plan_id']?.toString() ?? '',
      fecha: DateTime.tryParse(j['fecha']?.toString() ?? ''),
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble() ?? 0,
      totalAciertos: (j['total_aciertos'] as num?)?.toInt() ?? 0,
      totalIntentos: (j['total_intentos'] as num?)?.toInt() ?? 0,
      promedioTiempo: (j['promedio_tiempo'] as num?)?.toDouble() ?? 0,
      promedioAyuda: (j['promedio_ayuda'] as num?)?.toDouble() ?? 0,
      cumplimiento: (j['cumplimiento'] as num?)?.toDouble() ?? 0,
      habilidades: j['habilidades'] is List
          ? (j['habilidades'] as List)
              .map((e) => MetricaHabilidadProgreso.fromJson(e))
              .toList()
          : [],
    );
  }
}

class ObservacionProgreso {
  final String actividad;
  final String observacion;
  final DateTime? fecha;

  ObservacionProgreso({
    required this.actividad,
    required this.observacion,
    this.fecha,
  });

  factory ObservacionProgreso.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return ObservacionProgreso(
      actividad: j['actividad']?.toString() ?? 'Actividad',
      observacion: j['observacion']?.toString() ?? '',
      fecha: DateTime.tryParse(j['fecha']?.toString() ?? ''),
    );
  }
}

class MetricasProgreso {
  final String periodo;
  final int sesionesCompletadas;
  final double tasaAciertos;
  final double adherencia;
  final List<double> historiaAciertos;
  final List<MetricaHabilidadProgreso> metricasPorHabilidad;
  final List<SesionProgreso> sesiones;
  final List<ObservacionProgreso> observacionesRecientes;

  MetricasProgreso({
    this.periodo = 'Esta semana',
    required this.sesionesCompletadas,
    required this.tasaAciertos,
    required this.adherencia,
    required this.historiaAciertos,
    this.metricasPorHabilidad = const [],
    this.sesiones = const [],
    this.observacionesRecientes = const [],
  });

  factory MetricasProgreso.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return MetricasProgreso(
      periodo: j['periodo']?.toString() ?? 'Esta semana',
      sesionesCompletadas: (j['sesiones_completadas'] as num?)?.toInt() ?? 0,
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble() ?? 0,
      adherencia: (j['adherencia'] as num?)?.toDouble() ?? 0,
      historiaAciertos: j['historia_aciertos'] is List
          ? (j['historia_aciertos'] as List)
              .map((e) => (e as num).toDouble())
              .toList()
          : [0],
      metricasPorHabilidad: j['metricas_por_habilidad'] is List
          ? (j['metricas_por_habilidad'] as List)
              .map((e) => MetricaHabilidadProgreso.fromJson(e))
              .toList()
          : [],
      sesiones: j['sesiones'] is List
          ? (j['sesiones'] as List)
              .map((e) => SesionProgreso.fromJson(e))
              .toList()
          : [],
      observacionesRecientes: j['observaciones_recientes'] is List
          ? (j['observaciones_recientes'] as List)
              .map((e) => ObservacionProgreso.fromJson(e))
              .toList()
          : [],
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

class SolicitudAjusteData {
  final String id;
  final String accion;
  final String dificultadActual;
  final String dificultadSugerida;
  final String estado;
  final double? tasaAciertos;
  final int? muestras;
  final String? observacionTutor;

  SolicitudAjusteData({
    required this.id,
    required this.accion,
    required this.dificultadActual,
    required this.dificultadSugerida,
    required this.estado,
    this.tasaAciertos,
    this.muestras,
    this.observacionTutor,
  });

  factory SolicitudAjusteData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return SolicitudAjusteData(
      id: j['id']?.toString() ?? '',
      accion: j['accion']?.toString() ?? 'mantener',
      dificultadActual: j['dificultad_actual']?.toString() ?? 'Medio',
      dificultadSugerida: j['dificultad_sugerida']?.toString() ?? 'Medio',
      estado: j['estado']?.toString() ?? 'pendiente',
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble(),
      muestras: (j['muestras'] as num?)?.toInt(),
      observacionTutor: j['observacion_tutor']?.toString(),
    );
  }
}

class ActividadRevisionSesion {
  final String actividadId;
  final String actividadNombre;
  final String? instrucciones;
  final int aciertos;
  final int intentos;
  final double tasaAciertos;
  final String nivelDificultadUsado;
  final int nivelAyudaRequerido;
  final String? observaciones;
  final SolicitudAjusteData? solicitudAjuste;

  ActividadRevisionSesion({
    required this.actividadId,
    required this.actividadNombre,
    this.instrucciones,
    required this.aciertos,
    required this.intentos,
    required this.tasaAciertos,
    required this.nivelDificultadUsado,
    required this.nivelAyudaRequerido,
    this.observaciones,
    this.solicitudAjuste,
  });

  factory ActividadRevisionSesion.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return ActividadRevisionSesion(
      actividadId: j['actividad_id']?.toString() ?? '',
      actividadNombre: j['actividad_nombre']?.toString() ?? '',
      instrucciones: j['instrucciones']?.toString(),
      aciertos: (j['aciertos'] as num?)?.toInt() ?? 0,
      intentos: (j['intentos'] as num?)?.toInt() ?? 0,
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble() ?? 0,
      nivelDificultadUsado: j['nivel_dificultad_usado']?.toString() ?? 'Medio',
      nivelAyudaRequerido: (j['nivel_ayuda_requerido'] as num?)?.toInt() ?? 0,
      observaciones: j['observaciones']?.toString(),
      solicitudAjuste: j['solicitud_ajuste'] == null
          ? null
          : SolicitudAjusteData.fromJson(j['solicitud_ajuste']),
    );
  }
}

class SesionRevisionData {
  final String id;
  final String planId;
  final int sesionNumero;
  final DateTime? fecha;
  final double tasaAciertos;
  final int totalAciertos;
  final int totalIntentos;
  final List<ActividadRevisionSesion> actividades;

  SesionRevisionData({
    required this.id,
    required this.planId,
    required this.sesionNumero,
    this.fecha,
    required this.tasaAciertos,
    required this.totalAciertos,
    required this.totalIntentos,
    required this.actividades,
  });

  factory SesionRevisionData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return SesionRevisionData(
      id: j['id']?.toString() ?? '',
      planId: j['plan_id']?.toString() ?? '',
      sesionNumero: (j['sesion_numero'] as num?)?.toInt() ?? 1,
      fecha: DateTime.tryParse(j['fecha']?.toString() ?? ''),
      tasaAciertos: (j['tasa_aciertos'] as num?)?.toDouble() ?? 0,
      totalAciertos: (j['total_aciertos'] as num?)?.toInt() ?? 0,
      totalIntentos: (j['total_intentos'] as num?)?.toInt() ?? 0,
      actividades: j['actividades'] is List
          ? (j['actividades'] as List)
              .map((a) => ActividadRevisionSesion.fromJson(a))
              .toList()
          : [],
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

  Future<void> actualizarPerfilClinico(
    String ninoId,
    Map<String, dynamic> datos,
  ) async {
    await _dio.patch('/api/ninos/$ninoId/perfil-clinico', data: datos);
  }

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

  Future<List<SesionRevisionData>> obtenerSesionesRevision(
      String ninoId) async {
    final response = await _dio.get('/api/ninos/$ninoId/sesiones-revision');
    final data = _toMap(response.data);
    final sesiones = data['sesiones'];
    return sesiones is List
        ? sesiones.map((s) => SesionRevisionData.fromJson(s)).toList()
        : [];
  }

  Future<void> resolverSolicitudAjuste(
    String solicitudId, {
    required bool aceptar,
    String? observacion,
  }) async {
    await _dio.post(
      '/api/dashboard/terapeuta/solicitudes-ajuste/$solicitudId/resolver',
      data: {
        'aceptar': aceptar,
        if (observacion != null && observacion.trim().isNotEmpty)
          'observacion': observacion.trim(),
      },
    );
  }
}

class SesionService {
  SesionService(this._dio, this._localDb);
  final Dio _dio;
  final SqliteDbRepository _localDb;
  final Uuid _uuid = const Uuid();

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
    final actividadLocal = ActividadLocal(
      id: _uuid.v4(),
      ninoId: ninoId,
      planId: planId,
      actividadId: actividadId,
      aciertos: aciertos,
      repeticiones: intentos,
      tiempoRespuestaSegundos: segundos,
      nivelAyudaRequerido: _mapNivelAyuda(nivelAyuda),
      nivelDificultadUsado: nivelDificultadUsado,
      observaciones: observaciones,
      timestampLocal: DateTime.now(),
    );

    try {
      if (!await _hasConnectivity()) {
        await _localDb.saveActividad(actividadLocal);
        return _offlineResult(actividadLocal);
      }
      await sincronizarPendientes();
      final response = await _dio.post('/api/sesiones',
          data: actividadLocal.toSesionPayload(),
          options: Options(
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ));
      return {
        ...(response.data as Map).cast<String, dynamic>(),
        'pendiente_sync': false,
        'client_event_id': actividadLocal.id,
      };
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        await _localDb.saveActividad(actividadLocal);
        return _offlineResult(actividadLocal);
      }
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (detail is Map) {
        throw ActivitySaveException(
          detail['codigo']?.toString() ?? 'error_guardado',
          detail['mensaje']?.toString() ?? 'No se pudo guardar la actividad.',
        );
      }
      throw const ActivitySaveException(
        'error_guardado',
        'No se pudo guardar la actividad.',
      );
    }
  }

  Future<void> sincronizarPendientes() async {
    final pendientes = await _localDb.getActividadesPendientes();
    if (pendientes.isEmpty) return;

    final syncedIds = <String>[];
    for (final pendiente in pendientes) {
      try {
        await _dio.post('/api/sesiones', data: pendiente.toSesionPayload());
        syncedIds.add(pendiente.id);
      } on DioException catch (e) {
        if (_isNetworkFailure(e)) break;
      }
    }
    await _localDb.deleteActividades(syncedIds);
  }

  Future<bool> _hasConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool _isNetworkFailure(DioException e) {
    return e.response == null ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
  }

  int _mapNivelAyuda(String nivelAyuda) {
    return {
          'Ninguna': 0,
          'Verbal': 1,
          'Fisica': 2,
          'Física': 2,
        }[nivelAyuda] ??
        0;
  }

  Map<String, dynamic> _offlineResult(ActividadLocal actividadLocal) {
    return {
      'ok': true,
      'pendiente_sync': true,
      'sesion_id': actividadLocal.id,
      'client_event_id': actividadLocal.id,
      'total_aciertos': actividadLocal.aciertos,
      'total_intentos': actividadLocal.repeticiones,
      'tasa_aciertos': actividadLocal.repeticiones > 0
          ? actividadLocal.aciertos / actividadLocal.repeticiones
          : 0,
      'nivel_dificultad_recomendado':
          actividadLocal.nivelDificultadUsado,
      'ajustes_dificultad': [],
    };
  }

  Future<void> solicitarAjusteDificultad({
    required String sesionId,
    required String planId,
    required String actividadId,
    required String accion,
    required String dificultadActual,
    required String dificultadSugerida,
    double? tasaAciertos,
    int? muestras,
    String? observacion,
  }) async {
    await _dio.post('/api/sesiones/$sesionId/solicitud-ajuste', data: {
      'plan_id': planId,
      'actividad_id': actividadId,
      'accion': accion,
      'dificultad_actual': dificultadActual,
      'dificultad_sugerida': dificultadSugerida,
      if (tasaAciertos != null) 'tasa_aciertos': tasaAciertos,
      if (muestras != null) 'muestras': muestras,
      if (observacion != null && observacion.trim().isNotEmpty)
        'observacion': observacion.trim(),
    });
  }

  Future<void> guardarObservacion(String sesionId, String texto) async {}
}

class ActivitySaveException implements Exception {
  final String code;
  final String message;

  const ActivitySaveException(this.code, this.message);

  @override
  String toString() => message;
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
final sqliteDbRepositoryProvider = Provider((ref) => SqliteDbRepository());
final sesionServiceProvider =
    Provider((ref) => SesionService(
          ref.read(dioProvider),
          ref.read(sqliteDbRepositoryProvider),
        ));
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

final sesionesRevisionProvider =
    FutureProvider.family<List<SesionRevisionData>, String>((ref, ninoId) {
  return ref.read(iaServiceProvider).obtenerSesionesRevision(ninoId);
});

final nivelInicialProvider = FutureProvider.family<NivelInicialData,
    ({String ninoId, String actividadId})>((ref, args) {
  return ref
      .read(iaServiceProvider)
      .estimarNivelInicial(args.ninoId, args.actividadId);
});

final metricasProgresoFutureProvider =
    FutureProvider.family<MetricasProgreso,
        ({String ninoId, String periodo})>((ref, args) {
  return ref
      .read(indicadoresProgresoProvider)
      .obtenerMetricas(args.ninoId, args.periodo);
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
