import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/utils/clinical_document_utils.dart';

class ClinicalDocumentViewerScreen extends ConsumerStatefulWidget {
  const ClinicalDocumentViewerScreen({
    super.key,
    required this.document,
  });

  final ClinicalDocumentInfo document;

  @override
  ConsumerState<ClinicalDocumentViewerScreen> createState() =>
      _ClinicalDocumentViewerScreenState();
}

class _ClinicalDocumentViewerScreenState
    extends ConsumerState<ClinicalDocumentViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  PdfControllerPinch? _pdfController;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _bytes = null;
      _error = null;
      _pdfController?.dispose();
      _pdfController = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<List<int>>(
        widget.document.downloadPath,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw Exception('El documento esta vacio.');
      }

      final bytes = Uint8List.fromList(data);
      PdfControllerPinch? pdfController;
      if (ClinicalDocumentUtils.isPdf(
        widget.document.contentType,
        widget.document.fileName,
      )) {
        pdfController = PdfControllerPinch(
          document: PdfDocument.openData(bytes),
        );
      }

      if (!mounted) {
        pdfController?.dispose();
        return;
      }

      setState(() {
        _bytes = bytes;
        _pdfController = pdfController;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      final detail = e.response?.data;
      final message = status == 404
          ? 'Documento no encontrado en el servidor.'
          : 'No se pudo descargar el documento${status != null ? ' (HTTP $status)' : ''}.';
      setState(() {
        _error = detail is Map && detail['detail'] != null
            ? detail['detail'].toString()
            : message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFA43714)),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF58423B)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadDocument,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_bytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFA43714)),
      );
    }

    if (_pdfController != null) {
      return PdfViewPinch(controller: _pdfController!);
    }

    if (ClinicalDocumentUtils.isImage(
      widget.document.contentType,
      widget.document.fileName,
    )) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: Image.memory(_bytes!, fit: BoxFit.contain),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_drive_file_outlined,
                size: 48, color: Color(0xFF58423B)),
            const SizedBox(height: 16),
            const Text(
              'Este tipo de archivo no se puede previsualizar en la app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF58423B)),
            ),
            const SizedBox(height: 8),
            Text(
              widget.document.fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF2E9),
      appBar: RimAITopBar(
        title: widget.document.title,
        leadingIcon: Icons.description_outlined,
        iconColor: const Color(0xFFA43714),
        trailingWidget: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF58423B)),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _buildBody(),
    );
  }
}
