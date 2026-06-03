class ActividadLocal {
  final String id;
  final String ninoId;
  final String planId;
  final String actividadId;
  final int aciertos;
  final int repeticiones;
  final int tiempoRespuestaSegundos;
  final int nivelAyudaRequerido;
  final String nivelDificultadUsado;
  final String? observaciones;
  final DateTime timestampLocal;

  ActividadLocal({
    required this.id,
    required this.ninoId,
    required this.planId,
    required this.actividadId,
    required this.aciertos,
    required this.repeticiones,
    required this.tiempoRespuestaSegundos,
    required this.nivelAyudaRequerido,
    required this.nivelDificultadUsado,
    this.observaciones,
    required this.timestampLocal,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nino_id': ninoId,
      'plan_id': planId,
      'actividad_id': actividadId,
      'aciertos': aciertos,
      'repeticiones': repeticiones,
      'tiempo_respuesta_segundos': tiempoRespuestaSegundos,
      'nivel_ayuda_requerido': nivelAyudaRequerido,
      'nivel_dificultad_usado': nivelDificultadUsado,
      'observaciones': observaciones,
      'timestamp_local': timestampLocal.toIso8601String(),
    };
  }

  Map<String, dynamic> toSesionPayload() {
    return {
      'client_event_id': id,
      'nino_id': ninoId,
      'plan_id': planId,
      'resultados': [
        {
          'actividad_id': actividadId,
          'aciertos': aciertos,
          'repeticiones': repeticiones,
          'tiempo_respuesta': tiempoRespuestaSegundos.toDouble(),
          'nivel_ayuda_requerido': nivelAyudaRequerido,
          'nivel_dificultad_usado': nivelDificultadUsado,
          if (observaciones != null && observaciones!.trim().isNotEmpty)
            'observaciones': observaciones!.trim(),
        }
      ],
    };
  }

  factory ActividadLocal.fromJson(Map<String, dynamic> json) {
    return ActividadLocal(
      id: json['id']?.toString() ?? '',
      ninoId: json['nino_id']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? '',
      actividadId: json['actividad_id']?.toString() ?? '',
      aciertos: (json['aciertos'] as num?)?.toInt() ?? 0,
      repeticiones: (json['repeticiones'] as num?)?.toInt() ?? 0,
      tiempoRespuestaSegundos:
          (json['tiempo_respuesta_segundos'] as num?)?.toInt() ?? 0,
      nivelAyudaRequerido:
          (json['nivel_ayuda_requerido'] as num?)?.toInt() ?? 0,
      nivelDificultadUsado:
          json['nivel_dificultad_usado']?.toString() ?? 'Medio',
      observaciones: json['observaciones']?.toString(),
      timestampLocal: DateTime.tryParse(json['timestamp_local']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
