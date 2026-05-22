import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../application/ports/scq_port.dart';
import '../../domain/entities/scq_result.dart';

typedef TokenProvider = Future<String?> Function();

class ApiSCQRepository implements ISCQPort {
  final String baseUrl;
  final String? token;
  final TokenProvider? tokenProvider;

  ApiSCQRepository({
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
  Future<SCQResult> submitSCQ(
      String patientId, List<int> respuestas, bool aceptoDisclaimer) async {
    final headers = await _jsonAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/admision/scq'),
      headers: headers,
      body: jsonEncode({
        'patient_id': patientId,
        'respuestas': respuestas,
        'acepto_disclaimer': aceptoDisclaimer,
      }),
    );

    if (response.statusCode == 200) {
      return SCQResult.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al enviar el cuestionario SCQ: ${response.body}');
    }
  }

  @override
  Future<void> enviarCasoATerapeuta(String patientId) async {
    final headers = await _jsonAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/admision/$patientId/enviar-terapeuta'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al enviar el caso al terapeuta: ${response.body}');
    }
  }
}
