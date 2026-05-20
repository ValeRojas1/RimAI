import '../../domain/entities/actividad_local.dart';
import '../../domain/entities/reporte.dart';

abstract class ISyncPort {
  Future<bool> syncActividades(List<ActividadLocal> actividades);
  Future<ReporteAnalitico> fetchReporte(
      int patientId, DateTime inicio, DateTime fin);
}
