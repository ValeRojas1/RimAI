from typing import List, Union
from app.domain.entities.cuestionario_scq import CuestionarioSCQ, ResultadoScoring, NivelIndicioSCQ
from app.application.ports.scq_repository import ISCQRepository

class EvaluarCuestionarioSCQUseCase:
    def __init__(self, scq_repo: ISCQRepository):
        self.scq_repo = scq_repo

    def execute(
        self,
        patient_id: Union[int, str],
        tutor_id: Union[int, str],
        respuestas: List[int],
        acepto_disclaimer: bool,
    ) -> CuestionarioSCQ:
        if not acepto_disclaimer:
            raise ValueError("Debe aceptar el aviso legal (RNF-10) antes de enviar el cuestionario.")

        # Validar longitud y valores
        if len(respuestas) != 40:
            raise ValueError("Debe responder exactamente las 40 preguntas del cuestionario SCQ.")
        if not all(r in [0, 1] for r in respuestas):
            raise ValueError("Las respuestas del SCQ deben ser 0 o 1.")

        # Pregunta 1 (índice 0) es la pregunta filtro (gateway) y no se suma al puntaje
        habla_frases = respuestas[0] == 1

        # Preguntas que suman 1 punto si la respuesta es 'No' (valor 0)
        # 1-based: Q2, Q9, Q19, Q20 a Q40
        # 0-based indices: 1, 8, 18, y 19 a 39
        indices_no_scores_1 = {1, 8} | set(range(18, 40))

        # Preguntas que suman 1 punto si la respuesta es 'Sí' (valor 1)
        # 1-based: Q3 a Q8, Q10 a Q18
        # 0-based indices: 2 a 7, 9 a 17
        indices_yes_scores_1 = set(range(2, 8)) | set(range(9, 18))

        puntaje_total = 0
        for i in range(1, 40):
            # Si el niño no habla con frases cortas (Q1 = No), se omiten las preguntas 2 a 7 (índices 1 a 6)
            if not habla_frases and 1 <= i <= 6:
                continue

            val = respuestas[i]
            if i in indices_no_scores_1:
                if val == 0:
                    puntaje_total += 1
            elif i in indices_yes_scores_1:
                if val == 1:
                    puntaje_total += 1

        # Umbral Clínico SCQ (Típicamente >= 15 indica alto riesgo de TEA)
        # Bajo < 11, Moderado 11-14, Alto >= 15
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
