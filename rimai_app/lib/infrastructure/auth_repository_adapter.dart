import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';

/// Adaptador de salida: implementación HTTP del repositorio de autenticación.
/// Se comunica con el backend real a través de Dio (o puede ser mock).
class AuthRepositoryAdapter implements AuthRepositoryPort {
  // TODO: inyectar instancia de Dio cuando el backend esté disponible.
  // final Dio _dio;
  // const AuthRepositoryAdapter(this._dio);

  @override
  Future<Usuario> registrarUsuario(RegistroUsuarioRequest request) async {
    // --- Implementación real con Dio (descomentar cuando el backend esté listo) ---
    // final response = await _dio.post('/api/auth/register', data: {
    //   'nombre_completo': request.nombreCompleto,
    //   'correo': request.correo,
    //   'contrasena': request.contrasena,
    // });
    // return Usuario(
    //   id: response.data['id'],
    //   nombreCompleto: response.data['nombre_completo'],
    //   correo: response.data['correo'],
    //   rol: response.data['rol'],
    //   token: response.data['token'],
    // );

    // --- Mock temporal ---
    await Future.delayed(const Duration(seconds: 2));
    return Usuario(
      id: 'mock-uid-001',
      nombreCompleto: request.nombreCompleto,
      correo: request.correo,
      rol: 'tutor',
      token: 'mock-jwt-token',
    );
  }

  @override
  Future<Usuario> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    // --- Mock temporal ---
    await Future.delayed(const Duration(seconds: 2));
    return Usuario(
      id: 'mock-uid-001',
      nombreCompleto: 'Usuario Demo',
      correo: correo,
      rol: 'tutor',
      token: 'mock-jwt-token',
    );
  }
}
