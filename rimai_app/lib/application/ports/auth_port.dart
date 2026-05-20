import '../../domain/entities/user.dart';

abstract class AuthPort {
  Future<User?> login(String email, String password);
  Future<void> logout();
  Future<User?> getCurrentUser();
}
