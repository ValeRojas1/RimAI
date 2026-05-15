import 'package:dio/dio.dart';
import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';

import 'package:rimai_app/core/constants/api_constants.dart';

/// Adaptador de salida: implementación HTTP real del repositorio de autenticación.
/// Se comunica con el backend FastAPI a través de Dio.
class AuthRepositoryAdapter implements AuthRepositoryPort {
  late final Dio _dio;

  AuthRepositoryAdapter() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  @override
  Future<Usuario> registrarUsuario(RegistroUsuarioRequest request) async {
    try {
      final response = await _dio.post(
        '/api/auth/register',
        data: {
          'nombre': request.nombreCompleto,
          'email': request.correo,
          'password': request.contrasena,
        },
      );

      final data = response.data as Map<String, dynamic>;

      return Usuario(
        id: data['user_id'],
        nombreCompleto: data['nombre'],
        correo: request.correo,
        rol: data['rol'],
        token: data['access_token'],
      );
    } on DioException catch (e) {
      final message =
          e.response?.data?['detail'] ?? 'Error de conexión con el servidor';
      throw Exception('$message');
    }
  }

  @override
  Future<Usuario> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {'email': correo, 'password': contrasena},
      );

      final data = response.data as Map<String, dynamic>;

      return Usuario(
        id: data['user_id'],
        nombreCompleto: data['nombre'],
        correo: correo,
        rol: data['rol'],
        token: data['access_token'],
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final message =
          e.response?.data?['detail'] ?? 'Error de conexión con el servidor';

      if (statusCode == 401) {
        throw Exception('Email o contraseña incorrectos');
      } else if (statusCode == 403) {
        throw Exception('Cuenta inactiva. Contacta al administrador.');
      } else {
        throw Exception('$message');
      }
    }
  }
}
