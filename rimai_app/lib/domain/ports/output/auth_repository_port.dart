import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';

/// Puerto de salida (driven port) hacia el repositorio/API de autenticación.
/// La infraestructura implementa este contrato.
abstract class AuthRepositoryPort {
  /// Llama al backend para registrar un usuario nuevo.
  Future<Usuario> registrarUsuario(RegistroUsuarioRequest request);

  /// Llama al backend para iniciar sesión.
  Future<Usuario> iniciarSesion({
    required String correo,
    required String contrasena,
  });
}
