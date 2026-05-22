import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

import 'package:rimai_app/adapters/output/sqlite_db_repository.dart';
import 'package:rimai_app/adapters/output/api_sync_repository.dart';
import 'package:rimai_app/application/usecases/sync_offline_usecase.dart';
import 'package:rimai_app/core/constants/api_constants.dart';
import 'package:rimai_app/infrastructure/config/auth_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de SQLite (Offline-First PMV3)
  final localDb = SqliteDbRepository();
  await localDb.database; // Fuerza la creación/apertura de la BD

  // Configuración de Sincronización en Background
  const authStorage = AuthStorageService(FlutterSecureStorage());
  final apiSyncRepo = ApiSyncRepository(
    baseUrl: ApiConstants.baseUrl,
    tokenProvider: authStorage.getToken,
  );
  final syncUsecase = SyncOfflineUsecase(localDb, apiSyncRepo);

  // NOTA: Aquí se podría integrar connectivity_plus para disparar syncUsecase.execute()
  // al detectar red en onConnectivityChanged.listen(...)
  syncUsecase.execute(); // Intento inicial al abrir la app

  runApp(
    const ProviderScope(
      child: RimAIApp(),
    ),
  );
}

class RimAIApp extends ConsumerWidget {
  const RimAIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'RimAI — Plataforma Terapéutica',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: PMV2Theme.theme,
    );
  }
}
