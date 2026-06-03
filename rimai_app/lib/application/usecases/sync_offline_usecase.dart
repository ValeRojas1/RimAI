import '../ports/local_db_port.dart';
import '../ports/sync_port.dart';

class SyncOfflineUsecase {
  final ILocalDbPort localDbPort;
  final ISyncPort syncPort;

  SyncOfflineUsecase(this.localDbPort, this.syncPort);

  Future<void> execute() async {
    final pendientes = await localDbPort.getActividadesPendientes();

    if (pendientes.isNotEmpty) {
      final syncedIds = await syncPort.syncActividades(pendientes);
      if (syncedIds.isNotEmpty) {
        await localDbPort.deleteActividades(syncedIds);
      }
    }
  }
}
