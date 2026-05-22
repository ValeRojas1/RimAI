import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rimai_app/core/constants/api_constants.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';
import 'package:rimai_app/adapters/output/api_scq_repository.dart';
import 'package:rimai_app/application/ports/scq_port.dart';
import 'package:rimai_app/application/usecases/submit_scq_usecase.dart';
import 'package:rimai_app/infrastructure/config/auth_storage_service.dart';
import 'package:rimai_app/domain/entities/scq_result.dart';

class DynamicTokenSCQRepository implements ISCQPort {
  final AuthStorageService _authStorage;
  final String _baseUrl;

  DynamicTokenSCQRepository(this._authStorage, this._baseUrl);

  @override
  Future<SCQResult> submitSCQ(
      String patientId, List<int> respuestas, bool aceptoDisclaimer) async {
    final token = await _authStorage.getToken() ?? '';
    final repo = ApiSCQRepository(baseUrl: _baseUrl, token: token);
    return await repo.submitSCQ(patientId, respuestas, aceptoDisclaimer);
  }

  @override
  Future<void> enviarCasoATerapeuta(String patientId) async {
    final token = await _authStorage.getToken() ?? '';
    final repo = ApiSCQRepository(baseUrl: _baseUrl, token: token);
    return repo.enviarCasoATerapeuta(patientId);
  }
}

final scqRepositoryProvider = Provider<ISCQPort>((ref) {
  final authStorage = ref.watch(authStorageProvider);
  return DynamicTokenSCQRepository(authStorage, ApiConstants.baseUrl);
});

final submitSCQUsecaseProvider = Provider<SubmitSCQUsecase>((ref) {
  final repository = ref.watch(scqRepositoryProvider);
  return SubmitSCQUsecase(repository);
});
