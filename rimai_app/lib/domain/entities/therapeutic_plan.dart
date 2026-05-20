class SugerenciaActividad {
  final String actividadId;
  final String nombre;
  final String justificacion;

  SugerenciaActividad({
    required this.actividadId,
    required this.nombre,
    required this.justificacion,
  });

  factory SugerenciaActividad.fromJson(Map<String, dynamic> json) {
    return SugerenciaActividad(
      actividadId: json['actividad_id'],
      nombre: json['nombre'],
      justificacion: json['justificacion'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'actividad_id': actividadId,
      'nombre': nombre,
      'justificacion': justificacion,
    };
  }
}

class TherapeuticPlan {
  final int? id;
  final int patientId;
  final int terapeutaId;
  final String estado;
  final List<SugerenciaActividad> sugerencias;

  TherapeuticPlan({
    this.id,
    required this.patientId,
    required this.terapeutaId,
    required this.estado,
    required this.sugerencias,
  });

  factory TherapeuticPlan.fromJson(Map<String, dynamic> json) {
    var list = json['sugerencias'] as List;
    List<SugerenciaActividad> sugerenciasList =
        list.map((i) => SugerenciaActividad.fromJson(i)).toList();

    return TherapeuticPlan(
      id: json['id'],
      patientId: json['patient_id'],
      terapeutaId: json['terapeuta_id'],
      estado: json['estado'],
      sugerencias: sugerenciasList,
    );
  }
}
