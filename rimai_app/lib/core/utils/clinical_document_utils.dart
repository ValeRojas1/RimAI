import 'package:rimai_app/core/constants/api_constants.dart';

class ClinicalDocumentInfo {
  const ClinicalDocumentInfo({
    required this.title,
    required this.downloadPath,
    required this.fileName,
    this.contentType,
  });

  final String title;
  final String downloadPath;
  final String fileName;
  final String? contentType;

  ClinicalDocumentInfo copyWith({
    String? title,
    String? downloadPath,
    String? fileName,
    String? contentType,
  }) {
    return ClinicalDocumentInfo(
      title: title ?? this.title,
      downloadPath: downloadPath ?? this.downloadPath,
      fileName: fileName ?? this.fileName,
      contentType: contentType ?? this.contentType,
    );
  }
}

class ClinicalDocumentUtils {
  static const _evaluationsPrefix = '/api/files/evaluations/';

  static ClinicalDocumentInfo? parse(String docKey, dynamic value) {
    if (value == null) return null;

    String? rawUrl;
    String? fileName;
    String? contentType;

    if (value is Map) {
      rawUrl = _firstNonEmpty([
        value['url'],
        value['download_url'],
        value['path'],
      ]);
      fileName = _firstNonEmpty([value['nombre'], value['name']]);
      contentType = value['content_type']?.toString();
      rawUrl ??= fileName;
    } else {
      final raw = value.toString().trim();
      if (raw.isEmpty) return null;
      if (raw.startsWith('{') && raw.contains('url')) {
        return null;
      }
      rawUrl = raw;
      fileName = raw.split(RegExp(r'[\\/]')).last;
    }

    final downloadPath = resolveDownloadPath(rawUrl);
    if (downloadPath == null) return null;

    fileName ??= downloadPath.split('/').last;
    if (fileName.isEmpty) fileName = 'documento';

    return ClinicalDocumentInfo(
      title: fileName,
      downloadPath: downloadPath,
      fileName: fileName,
      contentType: contentType,
    );
  }

  static String? resolveDownloadPath(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return null;

    final trimmed = rawUrl.trim();

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      final base = Uri.parse(ApiConstants.baseUrl);
      if (uri.host == base.host) {
        return uri.hasEmptyPath ? null : uri.path;
      }
      return trimmed;
    }

    if (trimmed.startsWith(_evaluationsPrefix)) {
      return trimmed;
    }

    if (trimmed.startsWith('/api/')) {
      return trimmed;
    }

    if (trimmed.startsWith('/')) {
      return trimmed;
    }

    final encodedName = Uri.encodeComponent(trimmed.split(RegExp(r'[\\/]')).last);
    return '$_evaluationsPrefix$encodedName';
  }

  static String documentTypeLabel(String key) => switch (key) {
        'evaluacion_profesional' => 'Evaluacion profesional',
        'plan_terapeutico_previo' => 'Plan terapeutico previo',
        'medicacion' => 'Documento de medicacion',
        _ => key.replaceAll('_', ' '),
      };

  static String? documentUrl(dynamic value) => parse('', value)?.downloadPath;

  static String documentLabel(dynamic value) {
    if (value is Map) {
      return value['nombre']?.toString() ??
          value['name']?.toString() ??
          value['url']?.toString() ??
          'archivo';
    }
    return value?.toString() ?? 'archivo';
  }

  static bool isImage(String? contentType, String fileName) {
    final type = _normalizedContentType(contentType, fileName);
    return type.startsWith('image/');
  }

  static bool isPdf(String? contentType, String fileName) {
    final type = _normalizedContentType(contentType, fileName);
    return type == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
  }

  static String _normalizedContentType(String? contentType, String fileName) {
    if (contentType != null && contentType.isNotEmpty) {
      return contentType.toLowerCase();
    }
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }
}
