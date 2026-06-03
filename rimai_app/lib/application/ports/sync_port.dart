import '../../domain/entities/actividad_local.dart';
import '../../domain/entities/reporte.dart';

abstract class ISyncPort {
  Future<List<String>> syncActividades(List<ActividadLocal> actividades);
  Future<ReporteAnalitico> fetchReporte(
      int patientId, DateTime inicio, DateTime fin);
}
