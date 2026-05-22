import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../application/ports/plan_port.dart';
import '../../domain/entities/therapeutic_plan.dart';

typedef TokenProvider = Future<String?> Function();

class ApiPlanRepository implements IPlanPort {
  final String baseUrl;
  final String? token;
  final TokenProvider? tokenProvider;

  ApiPlanRepository({
    required this.baseUrl,
    this.token,
    this.tokenProvider,
  });

  Future<Map<String, String>> _jsonAuthHeaders() async {
    final currentToken = tokenProvider != null ? await tokenProvider!() : token;
    if (currentToken == null || currentToken.trim().isEmpty) {
      throw Exception('Sesion no autenticada. Inicia sesion nuevamente.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $currentToken',
    };
  }

  @override
  Future<TherapeuticPlan> generateSuggestedPlan(
      int patientId, Map<String, dynamic> perfilSensorial) async {
    final headers = await _jsonAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/planes/personalizar'),
      headers: headers,
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
  Future<TherapeuticPlan> validatePlan(
      int planId, List<SugerenciaActividad> modificaciones) async {
    final headers = await _jsonAuthHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/planes/$planId/validar'),
      headers: headers,
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
