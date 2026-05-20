import '../../domain/entities/scq_result.dart';

abstract class ISCQPort {
  Future<SCQResult> submitSCQ(
      int patientId, List<int> respuestas, bool aceptoDisclaimer);
}
