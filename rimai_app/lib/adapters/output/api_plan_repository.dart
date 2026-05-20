import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../application/ports/plan_port.dart';
import '../../domain/entities/therapeutic_plan.dart';

class ApiPlanRepository implements IPlanPort {
  final String baseUrl;
  final String token;

  ApiPlanRepository({required this.baseUrl, required this.token});

  @override
  Future<TherapeuticPlan> generateSuggestedPlan(int patientId, Map<String, dynamic> perfilSensorial) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/planes/personalizar'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'patient_id': patientId,
        'perfil_sensorial': perfilSensorial,
      }),
    );

    if (response.statusCode == 200) {
      return TherapeuticPlan.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al generar plan sugerido: ${response.body}');
    }
  }

  @override
  Future<TherapeuticPlan> validatePlan(int planId, List<SugerenciaActividad> modificaciones) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/planes/$planId/validar'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'modificaciones': modificaciones.map((m) => m.toJson()).toList(),
      }),
    );

    if (response.statusCode == 200) {
      return TherapeuticPlan.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al validar plan: ${response.body}');
    }
  }
}
