import '../ports/local_db_port.dart';
import '../ports/sync_port.dart';

class SyncOfflineUsecase {
  final ILocalDbPort localDbPort;
  final ISyncPort syncPort;

  SyncOfflineUsecase(this.localDbPort, this.syncPort);

  Future<void> execute() async {
    final pendientes = await localDbPort.getActividadesPendientes();

    if (pendientes.isNotEmpty) {
      bool success = await syncPort.syncActividades(pendientes);
      if (success) {
        // Obtenemos los IDs y los borramos o marcamos como sincronizados
        final ids = pendientes
            .map((actividad) => actividad.id)
            .whereType<String>()
            .toList();
        await localDbPort.deleteActividades(ids);
      }
    }
  }
}
