class SCQResult {
  final int? id;
  final String patientId;
  final int puntajeTotal;
  final String nivelIndicio;
  final bool enviadoTerapeuta;

  SCQResult({
    this.id,
    required this.patientId,
    required this.puntajeTotal,
    required this.nivelIndicio,
    this.enviadoTerapeuta = false,
  });

  factory SCQResult.fromJson(Map<String, dynamic> json) {
    return SCQResult(
      id: json['id'],
      patientId: json['patient_id']?.toString() ?? '',
      puntajeTotal: json['puntaje_total'],
      nivelIndicio: json['nivel_indicio'],
      enviadoTerapeuta: json['enviado_terapeuta'] == true,
    );
  }
}
