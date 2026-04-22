import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';
import 'package:rimai_app/domain/ports/input/registrar_usuario_port.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';

/// Caso de uso: Registrar Usuario.
/// Orquesta la lógica de negocio entre el puerto de entrada y el repositorio.
class RegistrarUsuarioUseCase implements RegistrarUsuarioPort {
  final AuthRepositoryPort _authRepository;

  const RegistrarUsuarioUseCase(this._authRepository);

  @override
  Future<Usuario> ejecutar(RegistroUsuarioRequest request) async {
    // Validaciones de dominio adicionales (complementan las del formulario UI)
    if (request.nombreCompleto.trim().isEmpty) {
      throw ArgumentError('El nombre completo no puede estar vacío.');
    }
    if (!_esEmailValido(request.correo)) {
      throw ArgumentError('El correo electrónico no tiene un formato válido.');
    }
    if (request.contrasena.length < 8) {
      throw ArgumentError('La contraseña debe tener al menos 8 caracteres.');
    }

    return _authRepository.registrarUsuario(request);
  }

  bool _esEmailValido(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }
}
