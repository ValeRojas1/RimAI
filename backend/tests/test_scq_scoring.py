import pytest
from app.application.usecases.evaluar_cuestionario_scq_usecase import EvaluarCuestionarioSCQUseCase
from app.domain.entities.cuestionario_scq import NivelIndicioSCQ, CuestionarioSCQ

class MockSCQRepo:
    def save_scq(self, scq: CuestionarioSCQ):
        scq.id = 1
        return scq
    def get_by_patient_id(self, patient_id):
        pass

def test_scq_requires_disclaimer():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    with pytest.raises(ValueError, match="Debe aceptar el aviso legal"):
        uc.execute(1, 1, [0, 0, 0], False)

def test_scq_scoring_bajo():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    scq = uc.execute(1, 1, [1] * 5 + [0] * 35, True) # Total 5
    assert scq.puntaje_total == 5
    assert scq.nivel_indicio == NivelIndicioSCQ.BAJO

def test_scq_scoring_moderado():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    scq = uc.execute(1, 1, [1] * 12 + [0] * 28, True) # Total 12
    assert scq.puntaje_total == 12
    assert scq.nivel_indicio == NivelIndicioSCQ.MODERADO

def test_scq_scoring_alto():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    scq = uc.execute(1, 1, [1] * 16 + [0] * 24, True) # Total 16
    assert scq.puntaje_total == 16
    assert scq.nivel_indicio == NivelIndicioSCQ.ALTO

def test_scq_invalid_answers():
    repo = MockSCQRepo()
    uc = EvaluarCuestionarioSCQUseCase(repo)
    with pytest.raises(ValueError, match="Las respuestas del SCQ deben ser 0 o 1"):
        uc.execute(1, 1, [2, 0, 1], True)
