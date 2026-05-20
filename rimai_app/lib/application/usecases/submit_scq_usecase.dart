import '../ports/scq_port.dart';
import '../../domain/entities/scq_result.dart';

class SubmitSCQUsecase {
  final ISCQPort scqPort;

  SubmitSCQUsecase(this.scqPort);

  Future<SCQResult> execute(int patientId, List<int> respuestas, bool aceptoDisclaimer) async {
    if (!aceptoDisclaimer) {
      throw Exception('Debe aceptar la advertencia legal obligatoria (RNF-10).');
    }
    return await scqPort.submitSCQ(patientId, respuestas, aceptoDisclaimer);
  }
}
