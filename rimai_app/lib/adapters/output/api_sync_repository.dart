import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../application/ports/sync_port.dart';
import '../../domain/entities/actividad_local.dart';
import '../../domain/entities/reporte.dart';

typedef TokenProvider = Future<String?> Function();

class ApiSyncRepository implements ISyncPort {
  final String baseUrl;
  final String? token;
  final TokenProvider? tokenProvider;

  ApiSyncRepository({
    required this.baseUrl,
    this.token,
    this.tokenProvider,
  });

  Future<String?> _readToken() async {
    final currentToken = tokenProvider != null ? await tokenProvider!() : token;
    if (currentToken == null || currentToken.trim().isEmpty) return null;
    return currentToken;
  }

  Future<Map<String, String>?> _jsonAuthHeaders() async {
    final currentToken = await _readToken();
    if (currentToken == null) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $currentToken',
    };
  }

  @override
  Future<List<String>> syncActividades(List<ActividadLocal> actividades) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return [];

    final syncedIds = <String>[];
    for (final actividad in actividades) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/sesiones'),
          headers: headers,
          body: jsonEncode(actividad.toSesionPayload()),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          syncedIds.add(actividad.id);
        }
      } catch (_) {
        // Se mantiene en cola local para un reintento posterior.
      }
    }
    return syncedIds;
  }

  @override
  Future<ReporteAnalitico> fetchReporte(
      int patientId, DateTime inicio, DateTime fin) async {
    final uri = Uri.parse('$baseUrl/api/v1/seguimiento/reportes/$patientId')
        .replace(queryParameters: {
      'inicio': inicio.toIso8601String(),
      'fin': fin.toIso8601String(),
    });
    final headers = await _jsonAuthHeaders();
    if (headers == null) {
      throw Exception('Sesion no autenticada. Inicia sesion nuevamente.');
    }

    final response = await http.get(
      uri,
      headers: headers,
    );

    if (response.statusCode == 200) {
      return ReporteAnalitico.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error fetching reporte: ${response.body}');
    }
  }
}
