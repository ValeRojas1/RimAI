import '../../domain/entities/actividad_local.dart';
import '../ports/local_db_port.dart';

class RegistrarActividadUsecase {
  final ILocalDbPort localDbPort;

  RegistrarActividadUsecase(this.localDbPort);

  Future<void> execute(ActividadLocal actividad) async {
    // Save to local SQLite database (offline-first)
    await localDbPort.saveActividad(actividad);
  }
}
