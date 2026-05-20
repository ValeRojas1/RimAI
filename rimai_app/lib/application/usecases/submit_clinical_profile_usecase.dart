import '../../domain/entities/patient_profile.dart';
import '../ports/patient_port.dart';

class SubmitClinicalProfileUseCase {
  final PatientPort _patientPort;

  SubmitClinicalProfileUseCase(this._patientPort);

  Future<void> execute(PatientProfile profile) async {
    // Validaciones atómicas
    if (profile.antecedentesClinicos.isEmpty) {
      throw Exception('Los antecedentes clínicos no pueden estar vacíos.');
    }
    if (profile.calmingRituals.isEmpty) {
      throw Exception('Debe registrar al menos un ritual de calma.');
    }

    await _patientPort.savePatientProfile(profile);
  }
}
