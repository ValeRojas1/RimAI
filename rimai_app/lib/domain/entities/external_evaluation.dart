class ExternalEvaluation {
  final int? id;
  final int patientId;
  final String fileUrl;
  final String uploadedBy;

  ExternalEvaluation({
    this.id,
    required this.patientId,
    required this.fileUrl,
    required this.uploadedBy,
  });
}
