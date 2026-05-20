import os
import joblib
import numpy as np
from app.domain.entities.support_level import SupportLevel

class AISupportUseCases:
    def __init__(self):
        self.model = None
        self._load_model()

    def _load_model(self):
        try:
            model_path = os.path.join(os.path.dirname(__file__), "..", "..", "ai", "models", "rf_support_level.pkl")
            if os.path.exists(model_path):
                self.model = joblib.load(model_path)
        except Exception:
            pass

    def estimate_support_level(self, edad: int, diagnostico_declarado: str, perfil_sensorial_score: int, contexto_familiar_score: int, scq_score: int = 0) -> SupportLevel:
        # Lógica rápida de <100ms
        if self.model:
            # Map diagnosis to int
            diag_map = {"TEA Leve": 1, "TEA Moderado": 2, "TEA Severo": 3}
            diag_int = diag_map.get(diagnostico_declarado, 2)
            
            X = np.array([[edad, diag_int, perfil_sensorial_score, contexto_familiar_score]])
            pred_idx = self.model.predict(X)[0]
            
            # Map 0, 1, 2 to SupportLevel
            levels = [SupportLevel.BAJO, SupportLevel.MEDIO, SupportLevel.ALTO]
            if 0 <= pred_idx < len(levels):
                return levels[pred_idx]
        
        # Fallback heurístico (Motor de Reglas + SCQ)
        score = perfil_sensorial_score + contexto_familiar_score
        
        # Si no hay doc (SCQ se toma) y es alto, o score general es crítico
        if scq_score >= 15 or score > 15 or edad < 4:
            return SupportLevel.ALTO
        elif scq_score >= 11 or score > 8:
            return SupportLevel.MEDIO
        else:
            return SupportLevel.BAJO
