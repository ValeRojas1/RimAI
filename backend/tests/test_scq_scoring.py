import pytest
from app.application.usecases.evaluar_cuestionario_scq_usecase import EvaluarCuestionarioSCQUseCase
from app.domain.entities.cuestionario_scq import NivelIndicioSCQ, CuestionarioSCQ

class MockSCQRepo:
    def save_scq(self, scq: CuestionarioSCQ):
        scq.id = 1
        return scq
    def get_by_patient_id(self, patient_id):
        pass
    def verify_tutor_owns_patient(self, patient_id, tutor_user_id):
        return True
    def authorize_send_to_therapist(self, patient_id, tutor_user_id):
        pass

def test_scq_requires_disclaimer():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    with pytest.raises(ValueError, match="Debe aceptar el aviso legal"):
        uc.execute(1, 1, [0] * 40, False)

# Perfil típico saludable (0 puntos):
# Q1=1 (habla frases)
# Q2=1 (conversación -> Sí = 0pt)
# Q3-Q8=0 (conductas repetitivas -> No = 0pt)
# Q9=1 (expresión facial -> Sí = 0pt)
# Q10-Q18=0 (conductas repetitivas -> No = 0pt)
# Q19=1 (amigo -> Sí = 0pt)
# Q20-Q40=1 (comportamientos 4-5 años -> Sí = 0pt)
def _get_typical_profile():
    return [1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] + [1] * 21

def test_scq_scoring_bajo():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    respuestas = _get_typical_profile()
    # Agregar 5 puntos de indicio/déficit:
    respuestas[18] = 0  # Q19: No -> +1pt
    respuestas[19] = 0  # Q20: No -> +1pt
    respuestas[20] = 0  # Q21: No -> +1pt
    respuestas[2] = 1   # Q3: Sí -> +1pt
    respuestas[3] = 1   # Q4: Sí -> +1pt
    scq = uc.execute(1, 1, respuestas, True)
    assert scq.puntaje_total == 5
    assert scq.nivel_indicio == NivelIndicioSCQ.BAJO

def test_scq_scoring_moderado():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    respuestas = _get_typical_profile()
    # Agregar 12 puntos de indicio/déficit:
    for idx in [18, 19, 20, 21, 22, 23]:  # 6 puntos (No -> +1pt)
        respuestas[idx] = 0
    for idx in [2, 3, 4, 5, 6, 7]:  # 6 puntos (Sí -> +1pt)
        respuestas[idx] = 1
    scq = uc.execute(1, 1, respuestas, True)
    assert scq.puntaje_total == 12
    assert scq.nivel_indicio == NivelIndicioSCQ.MODERADO

def test_scq_scoring_alto():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    respuestas = _get_typical_profile()
    # Agregar 16 puntos de indicio/déficit:
    for idx in range(18, 30):  # 12 puntos (No -> +1pt)
        respuestas[idx] = 0
    for idx in [2, 3, 4, 5]:  # 4 puntos (Sí -> +1pt)
        respuestas[idx] = 1
    scq = uc.execute(1, 1, respuestas, True)
    assert scq.puntaje_total == 16
    assert scq.nivel_indicio == NivelIndicioSCQ.ALTO

def test_scq_gateway_skip_logic():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    respuestas = _get_typical_profile()
    respuestas[0] = 0  # Q1: No (No habla en frases cortas) -> omitir Q2 a Q7

    # Marcamos las preguntas 2 a 7 (índices 1 a 6) con respuestas indicativas de déficit:
    respuestas[1] = 0  # Q2: No
    respuestas[2] = 1  # Q3: Sí
    respuestas[3] = 1  # Q4: Sí
    respuestas[4] = 1  # Q5: Sí
    respuestas[5] = 1  # Q6: Sí
    respuestas[6] = 1  # Q7: Sí

    # A pesar de estar en indicio/déficit, deben omitirse y dar 0 puntos
    scq = uc.execute(1, 1, respuestas, True)
    assert scq.puntaje_total == 0

def test_scq_invalid_length():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    with pytest.raises(ValueError, match="Debe responder exactamente las 40 preguntas"):
        uc.execute(1, 1, [0, 0, 0], True)

def test_scq_invalid_answers():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    with pytest.raises(ValueError, match="Las respuestas del SCQ deben ser 0 o 1"):
        uc.execute(1, 1, [2] + [0] * 39, True)
