import os
import joblib
import numpy as np
from typing import Tuple, Dict, Any
from datetime import date
import logging

logger = logging.getLogger(__name__)

class IMotorAdaptativo:
    """
    Interfaz para el Motor Adaptativo de Inteligencia Artificial.
    Permite intercambiar el modelo (ej. Random Forest -> Red Neuronal) sin afectar el sistema.
    """
    def predecir_dificultad(self, nino_data: Dict[str, Any]) -> Tuple[str, float]:
        """
        Devuelve el nivel de dificultad y la confianza de la predicción.
        """
        raise NotImplementedError()

class MotorAdaptativoRandomForest(IMotorAdaptativo):
    def __init__(self):
        self.model = None
        self._load_model()
        
    def _load_model(self):
        try:
            model_path = os.path.join(os.path.dirname(__file__), "models", "rf_dificultad.pkl")
            if os.path.exists(model_path):
                self.model = joblib.load(model_path)
                logger.info("Modelo RandomForest cargado exitosamente.")
            else:
                logger.warning("No se encontró el modelo rf_dificultad.pkl. Se usarán reglas heurísticas.")
        except Exception as e:
            logger.error(f"Error cargando el modelo: {e}")

    def _calcular_edad(self, fecha_nacimiento) -> int:
        if isinstance(fecha_nacimiento, str):
            fecha_nacimiento = date.fromisoformat(fecha_nacimiento)
        hoy = date.today()
        return hoy.year - fecha_nacimiento.year - ((hoy.month, hoy.day) < (fecha_nacimiento.month, fecha_nacimiento.day))

    def predecir_dificultad(self, nino_data: Dict[str, Any]) -> Tuple[str, float]:
        """
        Aplica el modelo Random Forest para predecir el nivel de dificultad.
        nino_data requiere: fecha_nacimiento, nivel_cognitivo, perfil_sensorial, objetivos_intervencion
        """
        # Extraer características
        edad = self._calcular_edad(nino_data.get('fecha_nacimiento', date.today()))
        
        nivel_str = nino_data.get('nivel_cognitivo', 'Medio')
        map_cognitivo = {'Bajo': 0, 'Medio': 1, 'Alto': 2}
        nivel_cognitivo = map_cognitivo.get(nivel_str, 1)
        
        # Calcular número de sensibilidades
        sensorial = nino_data.get('perfil_sensorial', {})
        if not isinstance(sensorial, dict):
            sensorial = {}
            
        num_sensibilidades = sum(len(sensorial.get(k, [])) for k in ['hipersensibilidad', 'hiposensibilidad', 'comportamientos_repetitivos', 'intereses_obsesivos'])
        
        # Número de objetivos
        objetivos = nino_data.get('objetivos_intervencion', [])
        num_objetivos = len(objetivos) if objetivos else 1
        
        # Inferencia
        if self.model:
            X = np.array([[edad, nivel_cognitivo, num_sensibilidades, num_objetivos]])
            pred_idx = self.model.predict(X)[0]
            
            # Confianza (probabilidad de la clase ganadora)
            proba = self.model.predict_proba(X)[0]
            confianza = float(np.max(proba))
        else:
            # Fallback heurístico si no hay modelo (ej. desarrollo)
            score = (nivel_cognitivo * 2) + (edad / 6) - (num_sensibilidades * 0.5)
            if score < 1.0: pred_idx = 0
            elif score > 3.0: pred_idx = 2
            else: pred_idx = 1
            confianza = 0.85 # dummy
            
        map_dificultad = {0: 'Básico', 1: 'Intermedio', 2: 'Avanzado'}
        dificultad = map_dificultad.get(pred_idx, 'Intermedio')
        
        return dificultad, confianza

motor_adaptativo = MotorAdaptativoRandomForest()
