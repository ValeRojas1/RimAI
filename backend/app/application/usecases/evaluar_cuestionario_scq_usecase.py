from typing import List
from app.domain.entities.cuestionario_scq import CuestionarioSCQ, ResultadoScoring, NivelIndicioSCQ
from app.application.ports.scq_repository import ISCQRepository

class EvaluarCuestionarioSCQUseCase:
    def __init__(self, scq_repo: ISCQRepository):
        self.scq_repo = scq_repo

    def execute(self, patient_id: int, tutor_id: int, respuestas: List[int], acepto_disclaimer: bool) -> CuestionarioSCQ:
        if not acepto_disclaimer:
            raise ValueError("Debe aceptar el aviso legal (RNF-10) antes de enviar el cuestionario.")

        # Validar puntajes
        if not all(r in [0, 1] for r in respuestas):
            raise ValueError("Las respuestas del SCQ deben ser 0 o 1.")

        puntaje_total = sum(respuestas)
        
        # Umbral Clínico SCQ (Típicamente > 15 indica alto riesgo de TEA)
        # Bajo < 10, Moderado 11-14, Alto >= 15
        if puntaje_total >= 15:
            nivel = NivelIndicioSCQ.ALTO
        elif puntaje_total >= 11:
            nivel = NivelIndicioSCQ.MODERADO
        else:
            nivel = NivelIndicioSCQ.BAJO

        scq = CuestionarioSCQ(
            patient_id=patient_id,
            tutor_id=tutor_id,
            respuestas=respuestas,
            puntaje_total=puntaje_total,
            nivel_indicio=nivel,
            acepto_disclaimer=acepto_disclaimer
        )
        
        return self.scq_repo.save_scq(scq)
