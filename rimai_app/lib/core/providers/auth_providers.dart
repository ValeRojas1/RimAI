import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rimai_app/infrastructure/auth_repository_adapter.dart';
import 'package:rimai_app/domain/ports/output/auth_repository_port.dart';

import 'package:rimai_app/application/use_cases/registrar_usuario_use_case.dart';
import 'package:rimai_app/domain/ports/input/registrar_usuario_port.dart';

import 'package:rimai_app/infrastructure/config/auth_storage_service.dart';
import 'package:rimai_app/application/use_cases/iniciar_sesion_use_case.dart';

/// Proveedor del Secure Storage nativo
final _secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Proveedor del servicio de almacenamiento de autenticación
final authStorageProvider = Provider<AuthStorageService>((ref) {
  final storage = ref.watch(_secureStorageProvider);
  return AuthStorageService(storage);
});

/// Proveedor del repositorio de autenticación (adaptador de salida).
final authRepositoryProvider = Provider<AuthRepositoryPort>((ref) {
  return AuthRepositoryAdapter();
});

/// Proveedor del caso de uso de registro (adaptador de entrada).
final registrarUsuarioUseCaseProvider = Provider<RegistrarUsuarioPort>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final storage = ref.watch(authStorageProvider);
  return RegistrarUsuarioUseCase(repo, storage);
});

/// Proveedor del caso de uso de Iniciar Sesión.
final iniciarSesionUseCaseProvider = Provider<IniciarSesionUseCase>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final storage = ref.watch(authStorageProvider);
  return IniciarSesionUseCase(repo, storage);
});
