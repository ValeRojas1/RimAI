import 'package:dio/dio.dart';
import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';

// Dispositivo físico con USB: usa 'adb reverse tcp:8000 tcp:8000' y deja localhost
// Emulador Android: cambia a 10.0.2.2
const String _kBaseUrl = 'http://localhost:8000';

/// Adaptador de salida: implementación HTTP real del repositorio de autenticación.
/// Se comunica con el backend FastAPI a través de Dio.
class AuthRepositoryAdapter implements AuthRepositoryPort {
  late final Dio _dio;

  AuthRepositoryAdapter() {
    _dio = Dio(BaseOptions(
      baseUrl: _kBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  @override
  Future<Usuario> registrarUsuario(RegistroUsuarioRequest request) async {
    // El endpoint de registro no está en el MVP — redirigir a login con mock
    await Future.delayed(const Duration(seconds: 1));
    return Usuario(
      id: 'mock-uid-001',
      nombreCompleto: request.nombreCompleto,
      correo: request.correo,
      rol: 'terapeuta',
      token: 'mock-jwt-token',
    );
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
      final message = e.response?.data?['detail'] ?? 'Error de conexión con el servidor';

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
