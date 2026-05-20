import '../../domain/entities/therapeutic_plan.dart';

abstract class IPlanPort {
  Future<TherapeuticPlan> generateSuggestedPlan(
      int patientId, Map<String, dynamic> perfilSensorial);
  Future<TherapeuticPlan> validatePlan(
      int planId, List<SugerenciaActividad> modificaciones);
}
