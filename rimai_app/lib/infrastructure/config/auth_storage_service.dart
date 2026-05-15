import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:rimai_app/core/constants/api_constants.dart';

class AuthStorageService {
  final FlutterSecureStorage _storage;

  const AuthStorageService(this._storage);

  static const String _keyJwtToken = 'jwt_token';
  static const String _keyUserRole = 'user_role';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';

  /// Guarda la sesión completa tras un login o registro exitoso
  Future<void> saveSession({
    required String token,
    required String role,
    required String userId,
    String? userName,
  }) async {
    await Future.wait([
      _storage.write(key: _keyJwtToken, value: token),
      _storage.write(key: _keyUserRole, value: role),
      _storage.write(key: _keyUserId, value: userId),
      if (userName != null) _storage.write(key: _keyUserName, value: userName),
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

  Future<String?> getUserId() async {
    try {
      return await _storage.read(key: _keyUserId);
    } catch (e) {
      return null;
    }
  }

  Future<String?> getUserName() async {
    try {
      final stored = await _storage.read(key: _keyUserName);
      if (stored != null && stored.isNotEmpty) return stored;
      final token = await getToken();
      if (token == null) return null;
      return JwtDecoder.decode(token)['nombre']?.toString();
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
      _storage.delete(key: _keyUserName),
    ]);
  }

  /// Verifica con el servidor que el token almacenado sigue siendo válido.
  /// Retorna `true` si el token es válido, `false` si expiró o es inválido.
  /// Si la verificación falla por conexión (sin red), retorna `true` para
  /// no bloquear al usuario sin necesidad.
  Future<bool> isTokenValidOnServer() async {
    final token = await getToken();
    if (token == null) return false;
    try {
      if (JwtDecoder.isExpired(token)) {
        await clearSession();
        return false;
      }
    } catch (_) {
      await clearSession();
      return false;
    }

    try {
      final dio = Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      await dio.get(
        '/api/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true; // Token válido
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Token expirado o inválido → limpiar sesión
        await clearSession();
        return false;
      }
      // Otro error (sin red, timeout) → asumir válido para no bloquear
      return true;
    } catch (_) {
      return true;
    }
  }
}
