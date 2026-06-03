import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rimai_app/core/constants/api_constants.dart';

class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException(
      [this.message = 'Sesion expirada. Por favor inicia sesion de nuevo.']);

  @override
  String toString() => message;
}

Map<String, dynamic> _toMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
  throw Exception(
      'Respuesta inesperada del servidor. Tipo: ${raw.runtimeType}');
}

Map<String, dynamic> _optionalMap(dynamic raw) {
  if (raw == null) return {};
  return _toMap(raw);
}

List<String> _stringList(dynamic raw) {
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return [];
}

double _numDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw?.toString() ?? '') ?? 0;
}

class UltimaSesion {
  final DateTime? fecha;
  final double? tasaAciertos;
  final String? estado;

  UltimaSesion({this.fecha, this.tasaAciertos, this.estado});

  factory UltimaSesion.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return UltimaSesion(
      fecha:
          j['fecha'] != null ? DateTime.tryParse(j['fecha'].toString()) : null,
      tasaAciertos: j['tasa_aciertos'] != null
          ? (j['tasa_aciertos'] as num).toDouble()
          : null,
      estado: j['estado']?.toString(),
    );
  }
}

class ProgresoFamiliar {
  final String periodo;
  final int sesionesCompletadas;
  final int actividadesRegistradas;
  final double tasaAciertos;
  final double cumplimiento;
  final double promedioAyuda;
  final double promedioTiempoSegundos;

  const ProgresoFamiliar({
    this.periodo = 'ultimos_30_dias',
    this.sesionesCompletadas = 0,
    this.actividadesRegistradas = 0,
    this.tasaAciertos = 0,
    this.cumplimiento = 0,
    this.promedioAyuda = 0,
    this.promedioTiempoSegundos = 0,
  });

  factory ProgresoFamiliar.fromJson(dynamic raw) {
    final j = _optionalMap(raw);
    return ProgresoFamiliar(
      periodo: j['periodo']?.toString() ?? 'ultimos_30_dias',
      sesionesCompletadas:
          (j['sesiones_completadas'] as num?)?.toInt() ?? 0,
      actividadesRegistradas:
          (j['actividades_registradas'] as num?)?.toInt() ?? 0,
      tasaAciertos: _numDouble(j['tasa_aciertos']),
      cumplimiento: _numDouble(j['cumplimiento']),
      promedioAyuda: _numDouble(j['promedio_ayuda']),
      promedioTiempoSegundos: _numDouble(j['promedio_tiempo_segundos']),
    );
  }
}

class RiesgoAbandono {
  final String nivel;
  final int score;
  final int umbralInactividadDias;
  final int diasSinActividad;
  final int sesiones14Dias;
  final int sesiones30Dias;
  final int sesionesInterrumpidas30Dias;
  final double tasaInterrupcion30Dias;
  final int actividadesPlan;
  final int actividadesPendientes;
  final double proporcionActividadesPendientes;
  final List<String> factores;
  final String notaClinica;

  const RiesgoAbandono({
    this.nivel = 'bajo',
    this.score = 0,
    this.umbralInactividadDias = 7,
    this.diasSinActividad = 0,
    this.sesiones14Dias = 0,
    this.sesiones30Dias = 0,
    this.sesionesInterrumpidas30Dias = 0,
    this.tasaInterrupcion30Dias = 0,
    this.actividadesPlan = 0,
    this.actividadesPendientes = 0,
    this.proporcionActividadesPendientes = 0,
    this.factores = const [],
    this.notaClinica =
        'Herramienta de apoyo clinico; no constituye diagnostico.',
  });

  factory RiesgoAbandono.fromJson(dynamic raw) {
    final j = _optionalMap(raw);
    return RiesgoAbandono(
      nivel: j['nivel']?.toString() ?? 'bajo',
      score: (j['score'] as num?)?.toInt() ?? 0,
      umbralInactividadDias:
          (j['umbral_inactividad_dias'] as num?)?.toInt() ?? 7,
      diasSinActividad: (j['dias_sin_actividad'] as num?)?.toInt() ?? 0,
      sesiones14Dias: (j['sesiones_14_dias'] as num?)?.toInt() ?? 0,
      sesiones30Dias: (j['sesiones_30_dias'] as num?)?.toInt() ?? 0,
      sesionesInterrumpidas30Dias:
          (j['sesiones_interrumpidas_30_dias'] as num?)?.toInt() ?? 0,
      tasaInterrupcion30Dias: _numDouble(j['tasa_interrupcion_30_dias']),
      actividadesPlan: (j['actividades_plan'] as num?)?.toInt() ?? 0,
      actividadesPendientes:
          (j['actividades_pendientes'] as num?)?.toInt() ?? 0,
      proporcionActividadesPendientes:
          _numDouble(j['proporcion_actividades_pendientes']),
      factores: _stringList(j['factores']),
      notaClinica: j['nota_clinica']?.toString() ??
          'Herramienta de apoyo clinico; no constituye diagnostico.',
    );
  }
}

class PacienteDashboard {
  final String id;
  final String nombre;
  final String? fechaNacimiento;
  final int edad;
  final String nivelCognitivo;
  final String? diagnostico;
  final String? planActivo;
  final String? planActivoId;
  final String? planEstado;
  final UltimaSesion? ultimaSesion;
  final ProgresoFamiliar progreso;
  final RiesgoAbandono riesgoAbandono;
  final List<String> recomendacionesActivas;
  final List<String> alertas;
  final String estadoClinico;
  final Map<String, dynamic> hitos;
  final Map<String, dynamic> sensorial;
  final List<String> intereses;
  final Map<String, dynamic> estimulosAversivos;
  final List<String> rutinasRegulacion;
  final Map<String, dynamic> documentosClinicos;
  final String? medicacionActual;
  final bool requiereScq;
  final bool scqCompletado;
  final bool scqAutorizadoEnvio;
  final int? scqPuntaje;
  final String? scqNivel;

  PacienteDashboard({
    required this.id,
    required this.nombre,
    this.fechaNacimiento,
    required this.edad,
    required this.nivelCognitivo,
    this.diagnostico,
    this.planActivo,
    this.planActivoId,
    this.planEstado,
    this.ultimaSesion,
    this.progreso = const ProgresoFamiliar(),
    this.riesgoAbandono = const RiesgoAbandono(),
    this.recomendacionesActivas = const [],
    this.alertas = const [],
    this.estadoClinico = 'pendiente_asignacion',
    this.hitos = const {},
    this.sensorial = const {},
    this.intereses = const [],
    this.estimulosAversivos = const {},
    this.rutinasRegulacion = const [],
    this.documentosClinicos = const {},
    this.medicacionActual,
    this.requiereScq = false,
    this.scqCompletado = false,
    this.scqAutorizadoEnvio = false,
    this.scqPuntaje,
    this.scqNivel,
  });

  factory PacienteDashboard.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return PacienteDashboard(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      fechaNacimiento: j['fecha_nacimiento']?.toString(),
      edad: (j['edad'] as num?)?.toInt() ?? 0,
      nivelCognitivo: j['nivel_cognitivo']?.toString() ?? '',
      diagnostico: j['diagnostico']?.toString(),
      planActivo: j['plan_activo']?.toString(),
      planActivoId: j['plan_activo_id']?.toString(),
      planEstado: j['plan_estado']?.toString(),
      ultimaSesion: j['ultima_sesion'] != null
          ? UltimaSesion.fromJson(j['ultima_sesion'])
          : null,
      progreso: ProgresoFamiliar.fromJson(j['progreso']),
      riesgoAbandono: RiesgoAbandono.fromJson(j['riesgo_abandono']),
      recomendacionesActivas: _stringList(j['recomendaciones_activas']),
      alertas: _stringList(j['alertas']),
      estadoClinico: j['estado_clinico']?.toString() ?? 'pendiente_asignacion',
      hitos: _optionalMap(j['hitos']),
      sensorial: _optionalMap(j['sensorial']),
      intereses: _stringList(j['intereses']),
      estimulosAversivos: _optionalMap(j['estimulos_aversivos']),
      rutinasRegulacion: _stringList(j['rutinas_regulacion']),
      documentosClinicos: _optionalMap(j['documentos_clinicos']),
      medicacionActual: j['medicacion_actual']?.toString(),
      requiereScq: j['requiere_scq'] == true,
      scqCompletado: j['scq_completado'] == true,
      scqAutorizadoEnvio: j['scq_autorizado_envio'] == true,
      scqPuntaje: (j['scq_puntaje'] as num?)?.toInt(),
      scqNivel: j['scq_nivel']?.toString(),
    );
  }
}

class DashboardData {
  final String? terapeutaId;
  final String? terapeutaNombre;
  final int totalPacientes;
  final int sesionesEstaSemana;
  final int alertasBajaAdherencia;
  final List<PacienteDashboard> pacientes;

  DashboardData({
    this.terapeutaId,
    this.terapeutaNombre,
    required this.totalPacientes,
    required this.sesionesEstaSemana,
    required this.alertasBajaAdherencia,
    required this.pacientes,
  });

  factory DashboardData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return DashboardData(
      terapeutaId: j['terapeuta_id']?.toString(),
      terapeutaNombre: j['terapeuta_nombre']?.toString(),
      totalPacientes: (j['total_pacientes'] as num?)?.toInt() ?? 0,
      sesionesEstaSemana: (j['sesiones_esta_semana'] as num?)?.toInt() ?? 0,
      alertasBajaAdherencia:
          (j['alertas_baja_adherencia'] as num?)?.toInt() ?? 0,
      pacientes: j['pacientes'] is List
          ? (j['pacientes'] as List)
              .map((p) => PacienteDashboard.fromJson(p))
              .toList()
          : [],
    );
  }
}

// ── Niño pendiente (bandeja del terapeuta) ───────────────────────────────────
class NinoPendiente {
  final String id;
  final String nombre;
  final int edad;
  final String estadoClinico;
  final DateTime fechaRegistro;
  final String? diagnostico;
  final String? comunicacion;
  final List<String> intereses;
  final String? tutorNombre;
  final Map<String, dynamic> documentosClinicos;
  final String? medicacionActual;
  final bool requiereScq;
  final bool scqCompletado;
  final int? scqPuntaje;
  final String? scqNivel;
  final Map<String, dynamic> hitos;
  final Map<String, dynamic> estimulosAversivos;
  final List<String> rutinasRegulacion;
  final Map<String, dynamic> sensorialFamilia;

  NinoPendiente({
    required this.id,
    required this.nombre,
    required this.edad,
    required this.estadoClinico,
    required this.fechaRegistro,
    this.diagnostico,
    this.comunicacion,
    this.intereses = const [],
    this.tutorNombre,
    this.documentosClinicos = const {},
    this.medicacionActual,
    this.requiereScq = false,
    this.scqCompletado = false,
    this.scqPuntaje,
    this.scqNivel,
    this.hitos = const {},
    this.estimulosAversivos = const {},
    this.rutinasRegulacion = const [],
    this.sensorialFamilia = const {},
  });

  factory NinoPendiente.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return NinoPendiente(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      edad: (j['edad'] as num?)?.toInt() ?? 0,
      estadoClinico: j['estado_clinico']?.toString() ?? 'pendiente_asignacion',
      fechaRegistro: j['fecha_registro'] != null
          ? DateTime.tryParse(j['fecha_registro'].toString()) ?? DateTime.now()
          : DateTime.now(),
      diagnostico: j['diagnostico']?.toString(),
      comunicacion: j['comunicacion']?.toString(),
      intereses: j['intereses'] is List
          ? (j['intereses'] as List).map((e) => e.toString()).toList()
          : [],
      tutorNombre: j['tutor_nombre']?.toString(),
      documentosClinicos: _optionalMap(j['documentos_clinicos']),
      medicacionActual: j['medicacion_actual']?.toString(),
      requiereScq: j['requiere_scq'] == true,
      scqCompletado: j['scq_completado'] == true,
      scqPuntaje: (j['scq_puntaje'] as num?)?.toInt(),
      scqNivel: j['scq_nivel']?.toString(),
      hitos: _optionalMap(j['hitos']),
      estimulosAversivos: _optionalMap(j['estimulos_aversivos']),
      rutinasRegulacion: _stringList(j['rutinas_regulacion']),
      sensorialFamilia: _optionalMap(j['sensorial_familia']),
    );
  }
}

class ActividadPlan {
  final String id;
  final String nombre;
  final String tipo;
  final String? instrucciones;
  final String nivelDificultad;
  final String nivelCatalogo;
  final int? duracionEstimada;
  final List<String> materiales;
  final List<String> recomendacionesAdaptadas;
  final String modoEjecucion;
  final bool requiereAcompanamiento;
  final bool completada;

  ActividadPlan({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.instrucciones,
    required this.nivelDificultad,
    this.nivelCatalogo = 'Medio',
    this.duracionEstimada,
    this.materiales = const [],
    this.recomendacionesAdaptadas = const [],
    this.modoEjecucion = 'acompanada',
    this.requiereAcompanamiento = true,
    this.completada = false,
  });

  factory ActividadPlan.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return ActividadPlan(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      tipo: j['tipo']?.toString() ?? '',
      instrucciones: j['instrucciones']?.toString(),
      nivelDificultad: j['nivel_dificultad']?.toString() ?? 'Medio',
      nivelCatalogo: j['nivel_catalogo']?.toString() ??
          j['nivel_dificultad']?.toString() ??
          'Medio',
      duracionEstimada: (j['duracion_estimada'] as num?)?.toInt(),
      materiales: _stringList(j['materiales']),
      recomendacionesAdaptadas: _stringList(j['recomendaciones_adaptadas']),
      modoEjecucion: j['modo_ejecucion']?.toString() ?? 'acompanada',
      requiereAcompanamiento: j['requiere_acompanamiento'] != false,
      completada: j['completada'] == true,
    );
  }
}

class ActividadCatalogo {
  final String id;
  final String nombre;
  final String categoria;
  final String nivelDificultad;
  final int duracionEstimada;
  final List<String> materiales;
  final String instrucciones;
  final bool asociado;

  ActividadCatalogo({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.nivelDificultad,
    required this.duracionEstimada,
    required this.materiales,
    required this.instrucciones,
    this.asociado = false,
  });

  factory ActividadCatalogo.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return ActividadCatalogo(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      categoria: (j['categoria'] ?? j['tipo'])?.toString() ?? '',
      nivelDificultad: j['nivel_dificultad']?.toString() ?? 'Medio',
      duracionEstimada: (j['duracion_estimada'] as num?)?.toInt() ?? 0,
      materiales: _stringList(j['materiales']),
      instrucciones: j['instrucciones']?.toString() ?? '',
      asociado: j['asociado'] == true,
    );
  }
}

class PlanData {
  final String id;
  final String nombre;
  final String ninoId;
  final String ninoNombre;
  final String nivelDificultadActual;
  final String estadoPlan;
  final bool publicadoParaTutor;
  final int limiteActividades;
  final int limiteDuracionSegundos;
  final int? nivelTeaValidado;
  final List<ActividadPlan> actividades;
  final int sesionNumero;

  PlanData({
    required this.id,
    required this.nombre,
    required this.ninoId,
    required this.ninoNombre,
    required this.nivelDificultadActual,
    this.estadoPlan = 'borrador',
    this.publicadoParaTutor = false,
    this.limiteActividades = 3,
    this.limiteDuracionSegundos = 3600,
    this.nivelTeaValidado,
    required this.actividades,
    this.sesionNumero = 1,
  });

  factory PlanData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return PlanData(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? 'Plan terapeutico',
      ninoId: j['nino_id']?.toString() ?? '',
      ninoNombre: j['nino_nombre']?.toString() ?? 'Paciente',
      nivelDificultadActual:
          j['nivel_dificultad_actual']?.toString() ?? 'Medio',
      estadoPlan: j['estado_plan']?.toString() ?? 'borrador',
      publicadoParaTutor: j['publicado_para_tutor'] == true,
      limiteActividades: (j['limite_actividades'] as num?)?.toInt() ?? 3,
      limiteDuracionSegundos:
          (j['limite_duracion_segundos'] as num?)?.toInt() ?? 3600,
      nivelTeaValidado: (j['nivel_tea_validado'] as num?)?.toInt(),
      actividades: j['actividades'] is List
          ? (j['actividades'] as List)
              .map((a) => ActividadPlan.fromJson(a))
              .toList()
          : [],
      sesionNumero: (j['sesion_numero'] as num?)?.toInt() ?? 1,
    );
  }
}

class NotificacionData {
  final String id;
  final String titulo;
  final String mensaje;
  final bool leido;
  final String createdAt;
  final String tipo;
  final String canal;
  final String estadoEnvio;
  final String? entidadTipo;
  final String? entidadId;
  final Map<String, dynamic> payload;

  NotificacionData({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.leido,
    required this.createdAt,
    this.tipo = 'general',
    this.canal = 'in_app',
    this.estadoEnvio = 'registrada',
    this.entidadTipo,
    this.entidadId,
    this.payload = const {},
  });

  factory NotificacionData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return NotificacionData(
      id: j['id']?.toString() ?? '',
      titulo: j['titulo']?.toString() ?? '',
      mensaje: j['mensaje']?.toString() ?? '',
      leido: j['leido'] == true,
      createdAt: j['created_at']?.toString() ?? '',
      tipo: j['tipo']?.toString() ?? 'general',
      canal: j['canal']?.toString() ?? 'in_app',
      estadoEnvio: j['estado_envio']?.toString() ?? 'registrada',
      entidadTipo: j['entidad_tipo']?.toString(),
      entidadId: j['entidad_id']?.toString(),
      payload: _optionalMap(j['payload']),
    );
  }
}

class DashboardService {
  DashboardService(this._dio);

  final Dio _dio;

  Future<DashboardData> obtenerResumen() async {
    try {
      final response = await _dio.get('/api/dashboard/resumen');
      return DashboardData.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw const SessionExpiredException();
      rethrow;
    }
  }

  Future<PlanData> obtenerPlanActivo(String ninoId) async {
    final response = await _dio.get('/api/ninos/$ninoId/plan');
    return PlanData.fromJson(response.data);
  }

  Future<Map<String, dynamic>> generarReporteTerapeutico({
    required String ninoId,
    DateTime? inicio,
    DateTime? fin,
  }) async {
    try {
      final response = await _dio.get(
        '/api/dashboard/terapeuta/ninos/$ninoId/reporte-terapeutico',
        queryParameters: {
          'formato': 'json',
          if (inicio != null) 'inicio': inicio.toIso8601String(),
          if (fin != null) 'fin': fin.toIso8601String(),
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al generar el reporte.'));
    }
  }

  Future<Uint8List> descargarReporteTerapeuticoPdf({
    required String ninoId,
    DateTime? inicio,
    DateTime? fin,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        '/api/dashboard/terapeuta/ninos/$ninoId/reporte-terapeutico',
        queryParameters: {
          'formato': 'pdf',
          if (inicio != null) 'inicio': inicio.toIso8601String(),
          if (fin != null) 'fin': fin.toIso8601String(),
        },
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al exportar el PDF.'));
    }
  }

  Future<List<ActividadCatalogo>> listarActividades({String? planId}) async {
    try {
      final response = await _dio.get(
        '/api/dashboard/terapeuta/actividades',
        queryParameters: {
          if (planId != null) 'plan_id': planId,
        },
      );
      final list = response.data as List? ?? [];
      return list.map((e) => ActividadCatalogo.fromJson(e)).toList();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al cargar actividades.'));
    }
  }

  Future<ActividadCatalogo> crearActividad(Map<String, dynamic> datos) async {
    try {
      final response = await _dio.post(
        '/api/dashboard/terapeuta/actividades',
        data: datos,
      );
      return ActividadCatalogo.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al registrar la actividad.'));
    }
  }

  Future<void> asociarActividadAPlan({
    required String planId,
    required String actividadId,
  }) async {
    try {
      await _dio.post(
        '/api/dashboard/terapeuta/planes/$planId/actividades/$actividadId',
      );
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al asociar la actividad.'));
    }
  }

  Future<void> reemplazarActividadEnPlan({
    required String planId,
    required String actividadId,
    required String nuevaActividadId,
  }) async {
    try {
      await _dio.patch(
        '/api/dashboard/terapeuta/planes/$planId/actividades/$actividadId/reemplazar/$nuevaActividadId',
      );
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al reemplazar la actividad.'));
    }
  }

  Future<void> desasociarActividadDePlan({
    required String planId,
    required String actividadId,
  }) async {
    try {
      await _dio.delete(
        '/api/dashboard/terapeuta/planes/$planId/actividades/$actividadId',
      );
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al remover la actividad del plan.'));
    }
  }

  Future<Map<String, dynamic>> actualizarDificultadActividad({
    required String planId,
    required String actividadId,
    required String nivelDificultad,
    String origen = 'manual',
    String? observacion,
    double? tasaAciertos,
    int? muestras,
  }) async {
    try {
      final response = await _dio.patch(
        '/api/dashboard/terapeuta/planes/$planId/actividades/$actividadId/dificultad',
        data: {
          'nivel_dificultad': nivelDificultad,
          'origen': origen,
          if (observacion != null && observacion.trim().isNotEmpty)
            'observacion': observacion.trim(),
          if (tasaAciertos != null) 'tasa_aciertos': tasaAciertos,
          if (muestras != null) 'muestras': muestras,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al actualizar dificultad.'));
    }
  }

  Future<Map<String, dynamic>> validarNivelTea({
    required String ninoId,
    required int nivelTea,
    String? observacion,
  }) async {
    try {
      final response = await _dio.patch(
        '/api/dashboard/terapeuta/ninos/$ninoId/validacion-tea',
        data: {
          'nivel_tea': nivelTea,
          if (observacion != null && observacion.trim().isNotEmpty)
            'observacion': observacion.trim(),
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al validar nivel TEA.'));
    }
  }

  Future<Map<String, dynamic>> actualizarEstadoPlan({
    required String planId,
    required String estado,
    String? observacion,
  }) async {
    try {
      final response = await _dio.patch(
        '/api/dashboard/terapeuta/planes/$planId/estado',
        data: {
          'estado': estado,
          if (observacion != null && observacion.trim().isNotEmpty)
            'observacion': observacion.trim(),
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(
          _extractDetail(e, 'Error al actualizar el estado del plan.'));
    }
  }

  Future<DashboardData> obtenerResumenFamilia() async {
    try {
      final response = await _dio.get('/api/dashboard/familia/resumen');
      return DashboardData.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw const SessionExpiredException();
      rethrow;
    }
  }

  String _extractDetail(DioException e, String defaultMsg) {
    try {
      final data = e.response?.data;
      if (data == null) return defaultMsg;
      if (data is Map) {
        return data['detail']?.toString() ?? defaultMsg;
      }
      if (data is String) {
        final trimmed = data.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            return decoded['detail']?.toString() ?? defaultMsg;
          }
        }
        if (data.length < 150) {
          return data;
        }
      }
      return defaultMsg;
    } catch (_) {
      return defaultMsg;
    }
  }

  Future<Map<String, dynamic>> guardarPerfilNino(
      Map<String, dynamic> datos) async {
    try {
      final response =
          await _dio.post('/api/dashboard/familia/paciente', data: datos);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al registrar el paciente.'));
    }
  }

  Future<Map<String, dynamic>> actualizarPerfilNino(
      String ninoId, Map<String, dynamic> datos) async {
    try {
      final response = await _dio.patch(
        '/api/dashboard/familia/paciente/$ninoId',
        data: datos,
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al actualizar el paciente.'));
    }
  }

  Future<void> eliminarPerfilNino(String ninoId) async {
    try {
      await _dio.delete('/api/dashboard/familia/paciente/$ninoId');
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al eliminar el paciente.'));
    }
  }

  Future<void> vincularPaciente(Map<String, dynamic> datos) async {
    try {
      await _dio.post('/api/dashboard/terapeuta/vincular-paciente',
          data: datos);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 409) {
        throw Exception(_extractDetail(e, 'Error al vincular el paciente.'));
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generarPlanIA(String ninoId) async {
    try {
      final response =
          await _dio.post('/api/dashboard/paciente/$ninoId/plan/generar');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'];
      if (detail is Map) {
        // 422 — perfil no listo (detail es un dict estructurado)
        throw Exception(detail['mensaje'] as String? ??
            'El perfil no está listo para generar el plan.');
      }
      throw Exception(_extractDetail(e, 'Error al generar plan con IA.'));
    }
  }

  Future<List<NinoPendiente>> obtenerPendientes() async {
    try {
      final response = await _dio.get('/api/dashboard/terapeuta/pendientes');
      final list = response.data as List? ?? [];
      return list.map((e) => NinoPendiente.fromJson(e)).toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw const SessionExpiredException();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> vincularPorId(String ninoId,
      {bool omitirPerfil = false}) async {
    try {
      final response = await _dio.post(
        '/api/dashboard/terapeuta/vincular/$ninoId',
        queryParameters: {
          if (omitirPerfil) 'omitir_perfil': 'true',
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al vincular el paciente.'));
    }
  }

  Future<Map<String, dynamic>> completarPerfilClinico(
      String ninoId, Map<String, dynamic> datos) async {
    try {
      final response =
          await _dio.patch('/api/ninos/$ninoId/perfil-clinico', data: datos);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al guardar el perfil clínico.'));
    }
  }

  Future<void> enviarCasoScqATerapeuta(String ninoId) async {
    try {
      await _dio.post('/api/v1/admision/$ninoId/enviar-terapeuta');
    } on DioException catch (e) {
      throw Exception(
          _extractDetail(e, 'Error al enviar el caso al terapeuta.'));
    }
  }

  Future<void> subirDocumentoClinico({
    required String ninoId,
    required String tipo,
    required String path,
    required String fileName,
  }) async {
    try {
      final formData = FormData.fromMap({
        'tipo': tipo,
        'file': await MultipartFile.fromFile(path, filename: fileName),
      });
      await _dio.post(
        '/api/dashboard/familia/paciente/$ninoId/documento',
        data: formData,
      );
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al adjuntar el documento.'));
    }
  }

  Future<List<NotificacionData>> obtenerNotificaciones() async {
    try {
      final response = await _dio.get('/api/dashboard/familia/notificaciones');
      final list = response.data as List? ?? [];
      return list.map((e) => NotificacionData.fromJson(e)).toList();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al obtener notificaciones.'));
    }
  }

  Future<void> marcarNotificacionLeida(String id) async {
    try {
      await _dio.patch('/api/dashboard/familia/notificaciones/$id/leer');
    } on DioException catch (e) {
      throw Exception(
          _extractDetail(e, 'Error al marcar notificación como leída.'));
    }
  }

  Future<List<NotificacionData>> obtenerNotificacionesTerapeuta() async {
    try {
      final response =
          await _dio.get('/api/dashboard/terapeuta/notificaciones');
      final list = response.data as List? ?? [];
      return list.map((e) => NotificacionData.fromJson(e)).toList();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al obtener notificaciones.'));
    }
  }

  Future<void> marcarNotificacionTerapeutaLeida(String id) async {
    try {
      await _dio.patch('/api/dashboard/terapeuta/notificaciones/$id/leer');
    } on DioException catch (e) {
      throw Exception(
          _extractDetail(e, 'Error al marcar notificacion como leida.'));
    }
  }
}

final _secureStorageProvider2 = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.read(_secureStorageProvider2);
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await storage.read(key: 'jwt_token');
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        await storage.delete(key: 'jwt_token');
        await storage.delete(key: 'user_role');
        await storage.delete(key: 'user_id');
        await storage.delete(key: 'user_name');
      }
      handler.next(error);
    },
  ));
  return dio;
});

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService(ref.read(dioProvider));
});

final dashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerResumen();
});

final familiaDashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerResumenFamilia();
});

final planActivoProvider =
    FutureProvider.autoDispose.family<PlanData, String>((ref, ninoId) {
  return ref.read(dashboardServiceProvider).obtenerPlanActivo(ninoId);
});

final actividadesCatalogoProvider = FutureProvider.autoDispose
    .family<List<ActividadCatalogo>, String?>((ref, planId) {
  return ref.read(dashboardServiceProvider).listarActividades(planId: planId);
});

/// Bandeja de espera: niños sin terapeuta asignado visibles para cualquier terapeuta.
final pendientesProvider =
    FutureProvider.autoDispose<List<NinoPendiente>>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerPendientes();
});

final notificacionesProvider =
    FutureProvider.autoDispose<List<NotificacionData>>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerNotificaciones();
});

final terapeutaNotificacionesProvider =
    FutureProvider.autoDispose<List<NotificacionData>>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerNotificacionesTerapeuta();
});
