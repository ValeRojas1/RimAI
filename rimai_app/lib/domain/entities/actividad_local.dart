class ActividadLocal {
  final String? id; // UUID
  final int patientId;
  final String actividadId;
  final int planId;
  final int tiempoEmpleadoSegundos;
  final int nivelApoyoRequerido;
  final String observaciones;
  final List<String> detonantesPresentados;
  final bool completada;
  final DateTime timestampLocal;

  ActividadLocal({
    this.id,
    required this.patientId,
    required this.actividadId,
    required this.planId,
    required this.tiempoEmpleadoSegundos,
    required this.nivelApoyoRequerido,
    required this.observaciones,
    required this.detonantesPresentados,
    required this.completada,
    required this.timestampLocal,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'actividad_id': actividadId,
      'plan_id': planId,
      'tiempo_empleado_segundos': tiempoEmpleadoSegundos,
      'nivel_apoyo_requerido': nivelApoyoRequerido,
      'observaciones': observaciones,
      'detonantes_presentados': detonantesPresentados,
      'completada': completada,
      'timestamp_local': timestampLocal.toIso8601String(),
    };
  }

  factory ActividadLocal.fromJson(Map<String, dynamic> json) {
    return ActividadLocal(
      id: json['id'],
      patientId: json['patient_id'],
      actividadId: json['actividad_id'],
      planId: json['plan_id'],
      tiempoEmpleadoSegundos: json['tiempo_empleado_segundos'],
      nivelApoyoRequerido: json['nivel_apoyo_requerido'],
      observaciones: json['observaciones'],
      detonantesPresentados: List<String>.from(json['detonantes_presentados'] ?? []),
      completada: json['completada'],
      timestampLocal: DateTime.parse(json['timestamp_local']),
    );
  }
}
