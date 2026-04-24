import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Base URL ──────────────────────────────────────────────────────────────────
// Dispositivo físico con USB: usa 'adb reverse tcp:8000 tcp:8000' y deja localhost
// Emulador Android: cambia a 10.0.2.2
const String _kBaseUrl = 'http://localhost:8000';

// ── Helpers de parsing seguros ────────────────────────────────────────────────

/// Convierte la respuesta de Dio a Map<String, dynamic> de forma segura.
/// Maneja respuestas ya decodificadas (Map) y sin decodificar (String).
Map<String, dynamic> _toMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
  throw Exception(
    'Respuesta inesperada del servidor. Tipo: ${raw.runtimeType}',
  );
}

// ── Modelos ───────────────────────────────────────────────────────────────────

class UltimaSesion {
  final DateTime? fecha;
  final double? tasaAciertos;
  final String? estado;

  UltimaSesion({this.fecha, this.tasaAciertos, this.estado});

  factory UltimaSesion.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return UltimaSesion(
      fecha: j['fecha'] != null
          ? DateTime.tryParse(j['fecha'].toString())
          : null,
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
  final UltimaSesion? ultimaSesion;

  PacienteDashboard({
    required this.id,
    required this.nombre,
    required this.edad,
    required this.nivelCognitivo,
    this.planActivo,
    this.ultimaSesion,
  });

  factory PacienteDashboard.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return PacienteDashboard(
      id: j['id']?.toString() ?? '',
      nombre: j['nombre']?.toString() ?? '',
      edad: (j['edad'] as num?)?.toInt() ?? 0,
      nivelCognitivo: j['nivel_cognitivo']?.toString() ?? '',
      planActivo: j['plan_activo']?.toString(),
      ultimaSesion: j['ultima_sesion'] != null
          ? UltimaSesion.fromJson(j['ultima_sesion'])
          : null,
    );
  }
}

class DashboardData {
  final int totalPacientes;
  final int sesionesEstaSemana;
  final int alertasBajaAdherencia;
  final List<PacienteDashboard> pacientes;

  DashboardData({
    required this.totalPacientes,
    required this.sesionesEstaSemana,
    required this.alertasBajaAdherencia,
    required this.pacientes,
  });

  factory DashboardData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return DashboardData(
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

  /// Datos de demostración cuando el backend no está disponible.
  static DashboardData mock() => DashboardData(
        totalPacientes: 1,
        sesionesEstaSemana: 3,
        alertasBajaAdherencia: 0,
        pacientes: [
          PacienteDashboard(
            id: 'mock-nino-001',
            nombre: 'Lucas Mendoza',
            edad: 7,
            nivelCognitivo: 'Medio',
            planActivo: 'plan-001',
            ultimaSesion: UltimaSesion(
              fecha: DateTime.now().subtract(const Duration(days: 3)),
              tasaAciertos: 0.76,
              estado: 'completada',
            ),
          ),
        ],
      );
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
      nivelDificultad: j['nivel_dificultad']?.toString() ?? '',
      duracionEstimada: (j['duracion_estimada'] as num?)?.toInt(),
    );
  }
}

class PlanData {
  final String id;
  final String nivelDificultadActual;
  final List<ActividadPlan> actividades;

  PlanData({
    required this.id,
    required this.nivelDificultadActual,
    required this.actividades,
  });

  factory PlanData.fromJson(dynamic raw) {
    final j = _toMap(raw);
    return PlanData(
      id: j['id']?.toString() ?? '',
      nivelDificultadActual: j['nivel_dificultad_actual']?.toString() ?? '',
      actividades: j['actividades'] is List
          ? (j['actividades'] as List)
              .map((a) => ActividadPlan.fromJson(a))
              .toList()
          : [],
    );
  }
}

// ── Servicio ──────────────────────────────────────────────────────────────────

class DashboardService {
  DashboardService(this._dio);

  final Dio _dio;

  Future<DashboardData> obtenerResumen() async {
    try {
      final response = await _dio.get('/api/dashboard/resumen');
      return DashboardData.fromJson(response.data);
    } on DioException catch (e) {
      // Si no hay backend (conexión rechazada), usa datos mock para demo
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return DashboardData.mock();
      }
      rethrow;
    }
  }

  Future<PlanData> obtenerPlanActivo(String ninoId) async {
    final response =
        await _dio.get('/api/dashboard/paciente/$ninoId/plan');
    return PlanData.fromJson(response.data);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _secureStorageProvider2 = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final _dioProvider = Provider<Dio>((ref) {
  final storage = ref.read(_secureStorageProvider2);
  final dio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
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
    onError: (error, handler) {
      handler.next(error);
    },
  ));
  return dio;
});

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  final dio = ref.read(_dioProvider);
  return DashboardService(dio);
});

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  return ref.read(dashboardServiceProvider).obtenerResumen();
});

final planActivoProvider =
    FutureProvider.family<PlanData, String>((ref, ninoId) {
  return ref.read(dashboardServiceProvider).obtenerPlanActivo(ninoId);
});
