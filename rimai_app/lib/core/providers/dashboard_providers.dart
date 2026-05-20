import 'dart:convert';

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

class PacienteDashboard {
  final String id;
  final String nombre;
  final int edad;
  final String nivelCognitivo;
  final String? planActivo;
  final String? planActivoId;
  final UltimaSesion? ultimaSesion;
  final String estadoClinico;

  PacienteDashboard({
    required this.id,
    required this.nombre,
    required this.edad,
    required this.nivelCognitivo,
    this.planActivo,
    this.planActivoId,
    this.ultimaSesion,
    this.estadoClinico = 'pendiente_asignacion',
  });

  factory PacienteDashboard.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return PacienteDashboard(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      edad: (j['edad'] as num?)?.toInt() ?? 0,
      nivelCognitivo: j['nivel_cognitivo']?.toString() ?? '',
      planActivo: j['plan_activo']?.toString(),
      planActivoId: j['plan_activo_id']?.toString(),
      ultimaSesion: j['ultima_sesion'] != null
          ? UltimaSesion.fromJson(j['ultima_sesion'])
          : null,
      estadoClinico: j['estado_clinico']?.toString() ?? 'pendiente_asignacion',
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
    );
  }
}

class ActividadPlan {
  final String id;
  final String nombre;
  final String tipo;
  final String? instrucciones;
  final String nivelDificultad;
  final int? duracionEstimada;

  ActividadPlan({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.instrucciones,
    required this.nivelDificultad,
    this.duracionEstimada,
  });

  factory ActividadPlan.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return ActividadPlan(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      tipo: j['tipo']?.toString() ?? '',
      instrucciones: j['instrucciones']?.toString(),
      nivelDificultad: j['nivel_dificultad']?.toString() ?? 'Medio',
      duracionEstimada: (j['duracion_estimada'] as num?)?.toInt(),
    );
  }
}

class PlanData {
  final String id;
  final String nombre;
  final String ninoId;
  final String ninoNombre;
  final String nivelDificultadActual;
  final List<ActividadPlan> actividades;

  PlanData({
    required this.id,
    required this.nombre,
    required this.ninoId,
    required this.ninoNombre,
    required this.nivelDificultadActual,
    required this.actividades,
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
      actividades: j['actividades'] is List
          ? (j['actividades'] as List)
              .map((a) => ActividadPlan.fromJson(a))
              .toList()
          : [],
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

  Future<Map<String, dynamic>> guardarPerfilNino(Map<String, dynamic> datos) async {
    try {
      final response = await _dio.post('/api/dashboard/familia/paciente', data: datos);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al registrar el paciente.'));
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
        throw Exception(
            detail['mensaje'] as String? ?? 'El perfil no está listo para generar el plan.');
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

  Future<Map<String, dynamic>> vincularPorId(String ninoId) async {
    try {
      final response = await _dio.post('/api/dashboard/terapeuta/vincular/$ninoId');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al vincular el paciente.'));
    }
  }

  Future<Map<String, dynamic>> completarPerfilClinico(
      String ninoId, Map<String, dynamic> datos) async {
    try {
      final response = await _dio.patch('/api/ninos/$ninoId/perfil-clinico', data: datos);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw Exception(_extractDetail(e, 'Error al guardar el perfil clínico.'));
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

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerResumen();
});

final familiaDashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerResumenFamilia();
});

final planActivoProvider =
    FutureProvider.autoDispose.family<PlanData, String>((ref, ninoId) {
  return ref.read(dashboardServiceProvider).obtenerPlanActivo(ninoId);
});

/// Bandeja de espera: niños sin terapeuta asignado visibles para cualquier terapeuta.
final pendientesProvider = FutureProvider.autoDispose<List<NinoPendiente>>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerPendientes();
});
