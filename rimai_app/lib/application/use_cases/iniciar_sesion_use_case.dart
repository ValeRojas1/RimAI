import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';
import 'package:rimai_app/infrastructure/config/auth_storage_service.dart';

class IniciarSesionUseCase {
  final AuthRepositoryPort _repository;
  final AuthStorageService _storageService;

  const IniciarSesionUseCase(this._repository, this._storageService);

  Future<Usuario> ejecutar({
    required String correo,
    required String contrasena,
  }) async {
    if (correo.trim().isEmpty || contrasena.trim().isEmpty) {
      throw ArgumentError('El correo y la contraseña son obligatorios.');
    }

    final usuario = await _repository.iniciarSesion(
      correo: correo,
      contrasena: contrasena,
    );

    // Guardar sesión utilizando el AuthStorageService
    if (usuario.token != null) {
      await _storageService.saveSession(
        token: usuario.token!,
        role: usuario.rol ?? '',
        userId: usuario.id ?? '',
        userName: usuario.nombreCompleto,
      );
    }

    return usuario;
  }
}
