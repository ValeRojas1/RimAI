import pytest
from app.application.usecases.ai_support_usecases import AISupportUseCases
from app.domain.entities.ai_support import SupportLevel

def test_prioritization_scq_alto():
    uc = AISupportUseCases()
    # Sin model, fallback heuristico. SCQ = 15 (ALTO)
    level = uc.estimate_support_level(edad=5, diagnostico_declarado="Ninguno", perfil_sensorial_score=2, contexto_familiar_score=2, scq_score=15)
    assert level == SupportLevel.ALTO

def test_prioritization_scq_moderado():
    uc = AISupportUseCases()
    level = uc.estimate_support_level(edad=5, diagnostico_declarado="Ninguno", perfil_sensorial_score=2, contexto_familiar_score=2, scq_score=12)
    assert level == SupportLevel.MEDIO

def test_prioritization_scq_bajo():
    uc = AISupportUseCases()
    level = uc.estimate_support_level(edad=5, diagnostico_declarado="Ninguno", perfil_sensorial_score=2, contexto_familiar_score=2, scq_score=5)
    assert level == SupportLevel.BAJO

def test_prioritization_critical_score_no_scq():
    uc = AISupportUseCases()
    # general score = 16 > 15
    level = uc.estimate_support_level(edad=5, diagnostico_declarado="Ninguno", perfil_sensorial_score=10, contexto_familiar_score=6, scq_score=0)
    assert level == SupportLevel.ALTO
