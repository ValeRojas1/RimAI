import 'package:rimai_app/domain/entities/usuario.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';

/// Puerto de entrada (driving port) para el registro de usuario.
/// Define el contrato que la capa de aplicación expone hacia los adaptadores de entrada.
abstract class RegistrarUsuarioPort {
  /// Registra un nuevo usuario y retorna el [Usuario] con su token y rol.
  Future<Usuario> ejecutar(RegistroUsuarioRequest request);
}
