class MetricaDesempeno {
  final String actividadId;
  final double promedioTiempo;
  final double promedioApoyo;
  final double tasaCompletitud;

  MetricaDesempeno({
    required this.actividadId,
    required this.promedioTiempo,
    required this.promedioApoyo,
    required this.tasaCompletitud,
  });

  factory MetricaDesempeno.fromJson(Map<String, dynamic> json) {
    return MetricaDesempeno(
      actividadId: json['actividad_id'],
      promedioTiempo: json['promedio_tiempo'].toDouble(),
      promedioApoyo: json['promedio_apoyo'].toDouble(),
      tasaCompletitud: json['tasa_completitud'].toDouble(),
    );
  }
}

class ReporteAnalitico {
  final int patientId;
  final DateTime periodoInicio;
  final DateTime periodoFin;
  final double tasaAdherenciaGlobal;
  final List<MetricaDesempeno> metricasPorActividad;
  final List<String> observacionesAgrupadas;
  final List<String> detonantesFrecuentes;

  ReporteAnalitico({
    required this.patientId,
    required this.periodoInicio,
    required this.periodoFin,
    required this.tasaAdherenciaGlobal,
    required this.metricasPorActividad,
    required this.observacionesAgrupadas,
    required this.detonantesFrecuentes,
  });

  factory ReporteAnalitico.fromJson(Map<String, dynamic> json) {
    return ReporteAnalitico(
      patientId: json['patient_id'],
      periodoInicio: DateTime.parse(json['periodo_inicio']),
      periodoFin: DateTime.parse(json['periodo_fin']),
      tasaAdherenciaGlobal: json['tasa_adherencia_global'].toDouble(),
      metricasPorActividad: (json['metricas_por_actividad'] as List)
          .map((m) => MetricaDesempeno.fromJson(m))
          .toList(),
      observacionesAgrupadas: List<String>.from(json['observaciones_agrupadas'] ?? []),
      detonantesFrecuentes: List<String>.from(json['detonantes_frecuentes'] ?? []),
    );
  }
}
