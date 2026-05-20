class SCQResult {
  final int? id;
  final int puntajeTotal;
  final String nivelIndicio;

  SCQResult({
    this.id,
    required this.puntajeTotal,
    required this.nivelIndicio,
  });

  factory SCQResult.fromJson(Map<String, dynamic> json) {
    return SCQResult(
      id: json['id'],
      puntajeTotal: json['puntaje_total'],
      nivelIndicio: json['nivel_indicio'],
    );
  }
}
