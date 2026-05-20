import '../../domain/entities/user.dart';
import '../ports/auth_port.dart';

class LoginUseCase {
  final AuthPort _authPort;

  LoginUseCase(this._authPort);

  Future<User?> execute(String email, String password) async {
    // Aquí el _authPort se encarga de guardar el JWT en secure storage
    // y decodificar los claims para retornar un User.
    return await _authPort.login(email, password);
  }
}
