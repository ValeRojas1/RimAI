import 'dart:convert';
import '../../domain/entities/patient_profile.dart';
import '../../application/ports/patient_port.dart';
import 'sqlite_local_database.dart';
import 'package:dio/dio.dart'; // Cliente HTTP

class ApiPatientRepository implements PatientPort {
  final SQLiteLocalDatabase _localDb;
  final Dio _dio;

  ApiPatientRepository(this._localDb, this._dio);

  @override
  Future<void> savePatientProfile(PatientProfile profile) async {
    try {
      // Intento de envío online
      await _dio.post('/api/v1/pacientes/perfil-clinico', data: profile.toJson());
    } catch (e) {
      // Si falla (offline en zonas rurales de Junín), guardar en SQLite
      final payload = jsonEncode(profile.toJson());
      await _localDb.queuePatientProfile(payload);
    }
  }

  @override
  Future<Map<String, dynamic>> getPatientHistory(int patientId) async {
    final response = await _dio.get('/api/v1/pacientes/$patientId/historial');
    return response.data;
  }

  @override
  Future<void> syncOfflineData() async {
    final unsynced = await _localDb.getUnsyncedProfiles();
    for (var row in unsynced) {
      try {
        await _dio.post('/api/v1/pacientes/perfil-clinico', data: jsonDecode(row['payload']));
        await _localDb.markAsSynced(row['id']);
      } catch (e) {
        // Ignorar y reintentar después
      }
    }
  }
}
