import 'dart:io';
import '../ports/file_port.dart';

class UploadEvaluationUseCase {
  final FilePort _filePort;

  UploadEvaluationUseCase(this._filePort);

  Future<String> execute(int patientId, File file) async {
    return await _filePort.uploadEvaluation(patientId, file);
  }
}
