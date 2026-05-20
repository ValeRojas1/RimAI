import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../application/ports/sync_port.dart';
import '../../domain/entities/actividad_local.dart';
import '../../domain/entities/reporte.dart';

class ApiSyncRepository implements ISyncPort {
  final String baseUrl;
  final String token;

  ApiSyncRepository({required this.baseUrl, required this.token});

  @override
  Future<bool> syncActividades(List<ActividadLocal> actividades) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/seguimiento/sincronizar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'actividades': actividades.map((a) => a.toJson()).toList(),
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false; // Error de red, mantiene offline
    }
  }

  @override
  Future<ReporteAnalitico> fetchReporte(int patientId, DateTime inicio, DateTime fin) async {
    final uri = Uri.parse('$baseUrl/api/v1/seguimiento/reportes/$patientId').replace(queryParameters: {
      'inicio': inicio.toIso8601String(),
      'fin': fin.toIso8601String(),
    });

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return ReporteAnalitico.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error fetching reporte: ${response.body}');
    }
  }
}
