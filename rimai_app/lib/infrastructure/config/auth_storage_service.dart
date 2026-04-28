import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorageService {
  final FlutterSecureStorage _storage;

  const AuthStorageService(this._storage);

  static const String _keyJwtToken = 'jwt_token';
  static const String _keyUserRole = 'user_role';
  static const String _keyUserId = 'user_id';

  /// Guarda la sesión completa tras un login o registro exitoso
  Future<void> saveSession({
    required String token,
    required String role,
    required String userId,
  }) async {
    await Future.wait([
      _storage.write(key: _keyJwtToken, value: token),
      _storage.write(key: _keyUserRole, value: role),
      _storage.write(key: _keyUserId, value: userId),
    ]);
  }

  /// Recupera el token JWT
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _keyJwtToken);
    } catch (e) {
      await clearSession(); // Limpiar si hay corrupción de llaves en Android
      return null;
    }
  }

  /// Recupera el rol del usuario
  Future<String?> getRole() async {
    try {
      return await _storage.read(key: _keyUserRole);
    } catch (e) {
      return null;
    }
  }

  /// Limpia la sesión actual
  Future<void> clearSession() async {
    await Future.wait([
      _storage.delete(key: _keyJwtToken),
      _storage.delete(key: _keyUserRole),
      _storage.delete(key: _keyUserId),
    ]);
  }
}
