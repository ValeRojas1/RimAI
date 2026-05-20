import '../../domain/entities/actividad_local.dart';

abstract class ILocalDbPort {
  Future<void> saveActividad(ActividadLocal actividad);
  Future<List<ActividadLocal>> getActividadesPendientes();
  Future<void> deleteActividades(List<String> ids);
}
