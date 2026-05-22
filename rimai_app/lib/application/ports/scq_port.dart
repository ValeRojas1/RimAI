import '../../domain/entities/scq_result.dart';

abstract class ISCQPort {
  Future<SCQResult> submitSCQ(
      String patientId, List<int> respuestas, bool aceptoDisclaimer);

  Future<void> enviarCasoATerapeuta(String patientId);
}
