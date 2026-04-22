import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rimai_app/infrastructure/auth_repository_adapter.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';
import 'package:rimai_app/application/use_cases/registrar_usuario_use_case.dart';
import 'package:rimai_app/domain/ports/input/registrar_usuario_port.dart';

/// Proveedor del repositorio de autenticación (adaptador de salida).
final authRepositoryProvider = Provider<AuthRepositoryPort>((ref) {
  return AuthRepositoryAdapter();
});

/// Proveedor del caso de uso de registro (adaptador de entrada).
final registrarUsuarioUseCaseProvider = Provider<RegistrarUsuarioPort>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return RegistrarUsuarioUseCase(repo);
});
