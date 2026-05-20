import '../../domain/entities/patient_profile.dart';

abstract class PatientPort {
  Future<void> savePatientProfile(PatientProfile profile);
  Future<Map<String, dynamic>> getPatientHistory(int patientId);
  Future<void> syncOfflineData();
}
