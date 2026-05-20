import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../application/ports/scq_port.dart';
import '../../domain/entities/scq_result.dart';

class ApiSCQRepository implements ISCQPort {
  final String baseUrl;
  final String token;

  ApiSCQRepository({required this.baseUrl, required this.token});

  @override
  Future<SCQResult> submitSCQ(int patientId, List<int> respuestas, bool aceptoDisclaimer) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/admision/scq'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
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
}
