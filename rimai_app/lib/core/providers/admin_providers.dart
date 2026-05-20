import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rimai_app/core/constants/api_constants.dart';

class UsuarioAdmin {
  final String id;
  final String nombre;
  final String email;
  final String rol;
  final bool activo;
  final DateTime createdAt;

  UsuarioAdmin({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activo,
    required this.createdAt,
  });

  factory UsuarioAdmin.fromJson(Map<String, dynamic> json) {
    return UsuarioAdmin(
      id: json['id'],
      nombre: json['nombre'],
      email: json['email'],
      rol: json['rol'],
      activo: json['activo'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class AdminEstadisticas {
  final int totalTerapeutas;
  final int totalFamilias;
  final int totalNinos;
  final int totalSesiones;

  AdminEstadisticas({
    required this.totalTerapeutas,
    required this.totalFamilias,
    required this.totalNinos,
    required this.totalSesiones,
  });

  factory AdminEstadisticas.fromJson(Map<String, dynamic> json) {
    return AdminEstadisticas(
      totalTerapeutas: json['total_terapeutas'] ?? 0,
      totalFamilias: json['total_familias'] ?? 0,
      totalNinos: json['total_ninos'] ?? 0,
      totalSesiones: json['total_sesiones'] ?? 0,
    );
  }
}

class AdminService {
  AdminService(this._dio);
  final Dio _dio;

  Future<AdminEstadisticas> obtenerEstadisticas() async {
    final response = await _dio.get('/api/admin/estadisticas');
    return AdminEstadisticas.fromJson(response.data);
  }

  Future<List<UsuarioAdmin>> listarUsuarios() async {
    final response = await _dio.get('/api/admin/usuarios');
    final List data = response.data;
    return data.map((json) => UsuarioAdmin.fromJson(json)).toList();
  }

  Future<void> crearUsuario(
      String nombre, String email, String password, String rol,
      {String? especialidad, String? colegiatura}) async {
    await _dio.post('/api/admin/usuarios', data: {
      'nombre': nombre,
      'email': email,
      'password': password,
      'rol': rol,
      if (especialidad != null && especialidad.isNotEmpty)
        'especialidad': especialidad,
      if (colegiatura != null && colegiatura.isNotEmpty)
        'colegiatura': colegiatura,
    });
  }

  Future<void> actualizarEstado(String id, bool activo) async {
    await _dio.patch('/api/admin/usuarios/$id/status', data: {
      'activo': activo,
    });
  }

  Future<void> eliminarUsuario(String id) async {
    try {
      await _dio.delete('/api/admin/usuarios/$id');
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 409) {
        final data = e.response?.data;
        final detail = (data is Map) ? data['detail']?.toString() : null;
        throw Exception(detail ?? 'No se puede eliminar el usuario');
      }
      rethrow;
    }
  }
}

final _adminDioProvider = Provider<Dio>((ref) {
  const storage = FlutterSecureStorage();
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
  ));
  return dio;
});

final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService(ref.read(_adminDioProvider));
});

final listaUsuariosProvider = FutureProvider<List<UsuarioAdmin>>((ref) async {
  return ref.read(adminServiceProvider).listarUsuarios();
});

final estadisticasAdminProvider =
    FutureProvider<AdminEstadisticas>((ref) async {
  return ref.read(adminServiceProvider).obtenerEstadisticas();
});
