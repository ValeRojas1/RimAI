from datetime import datetime, timezone

from app.adapters.inbound.api.dashboard_controller import _evaluar_ajuste_dificultad


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows
        self.executions = []
        self.decision = {
            "id": "decision-1",
            "created_at": datetime(2026, 5, 21, 12, 0, tzinfo=timezone.utc),
        }

    def execute(self, query, params=None):
        self.executions.append((query, params))

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.decision

    @property
    def write_executions(self):
        return self.executions[1:]


def _row(aciertos, repeticiones, nivel_actual="Medio"):
    return {
        "aciertos": aciertos,
        "repeticiones": repeticiones,
        "nivel_dificultad_usado": nivel_actual,
        "actividad_nombre": "Clasificacion visual",
        "terapeuta_id": "terapeuta-1",
        "nivel_dificultad_actual": nivel_actual,
    }


def test_ajuste_dificultad_aumenta_con_desempeno_mayor_o_igual_a_80():
    cursor = FakeCursor([
        _row(8, 10, "Medio"),
        _row(8, 10, "Medio"),
    ])

    ajuste = _evaluar_ajuste_dificultad(
        cursor,
        nino_id="nino-1",
        plan_id="plan-1",
        actividad_id="actividad-1",
    )

    assert ajuste is not None
    assert ajuste["accion"] == "aumentar"
    assert ajuste["tasa_aciertos"] == 0.8
    assert ajuste["dificultad_actual"] == "Medio"
    assert ajuste["dificultad_sugerida"] == "Alto"
    assert ajuste["registrado"] is True

    update_params = cursor.write_executions[0][1]
    insert_params = cursor.write_executions[1][1]
    assert update_params[0] == "Alto"
    assert insert_params[3] == "AUMENTAR_DIFICULTAD"


def test_ajuste_dificultad_reduce_con_desempeno_menor_a_40():
    cursor = FakeCursor([
        _row(1, 5, "Medio"),
        _row(2, 5, "Medio"),
    ])

    ajuste = _evaluar_ajuste_dificultad(
        cursor,
        nino_id="nino-1",
        plan_id="plan-1",
        actividad_id="actividad-1",
    )

    assert ajuste is not None
    assert ajuste["accion"] == "reducir"
    assert ajuste["tasa_aciertos"] == 0.3
    assert ajuste["dificultad_actual"] == "Medio"
    assert ajuste["dificultad_sugerida"] == "Bajo"
    assert ajuste["registrado"] is True

    update_params = cursor.write_executions[0][1]
    insert_params = cursor.write_executions[1][1]
    assert update_params[0] == "Bajo"
    assert insert_params[3] == "REDUCIR_DIFICULTAD"


def test_ajuste_dificultad_no_registra_sin_resultados_previos_suficientes():
    cursor = FakeCursor([
        _row(10, 10, "Medio"),
    ])

    ajuste = _evaluar_ajuste_dificultad(
        cursor,
        nino_id="nino-1",
        plan_id="plan-1",
        actividad_id="actividad-1",
    )

    assert ajuste is None
    assert cursor.write_executions == []
