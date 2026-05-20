import '../ports/plan_port.dart';
import '../../domain/entities/therapeutic_plan.dart';

class ValidatePlanUsecase {
  final IPlanPort planPort;

  ValidatePlanUsecase(this.planPort);

  Future<TherapeuticPlan> execute(int planId, List<SugerenciaActividad> modificaciones) async {
    return await planPort.validatePlan(planId, modificaciones);
  }
}
