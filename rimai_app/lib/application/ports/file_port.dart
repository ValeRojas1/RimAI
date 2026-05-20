import 'dart:io';

abstract class FilePort {
  Future<String> uploadEvaluation(int patientId, File file);
}
