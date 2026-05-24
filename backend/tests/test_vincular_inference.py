from app.adapters.inbound.api.dashboard_controller import _infer_nivel_tea, _objetivos_desde_perfil

def test_infer_nivel_tea_nivel3_in_text():
    assert _infer_nivel_tea("Niño con autismo nivel 3", {}) == 3

def test_infer_nivel_tea_nivel2_in_text():
    assert _infer_nivel_tea("Nivel II diagnósis", {}) == 2

def test_infer_nivel_tea_scq_alto():
    perfil = {
        "triaje": {
            "scq": {
                "nivel_indicio": "Alto"
            }
        }
    }
    assert _infer_nivel_tea("Sospecha de TEA", perfil) == 3

def test_infer_nivel_tea_scq_moderado():
    perfil = {
        "triaje": {
            "scq": {
                "nivel_indicio": "Moderado"
            }
        }
    }
    assert _infer_nivel_tea("Sospecha de TEA", perfil) == 2

def test_infer_nivel_tea_default():
    assert _infer_nivel_tea("Sospecha de TEA", {}) == 1

def test_objetivos_desde_perfil_comunicacion():
    perfil = {
        "hitos": {
            "comunicacion": "Habla palabras sueltas"
        }
    }
    objs = _objetivos_desde_perfil(perfil)
    assert "Fortalecer comunicacion funcional (Habla palabras sueltas)." in objs

def test_objetivos_desde_perfil_rutinas():
    perfil = {
        "rutinas_regulacion": ["mecerse en hamaca"]
    }
    objs = _objetivos_desde_perfil(perfil)
    assert "Usar rutinas de regulacion registradas por la familia." in objs

def test_objetivos_desde_perfil_sensorial():
    perfil = {
        "sensorial": {
            "hipersensibilidad": ["ruidos"]
        }
    }
    objs = _objetivos_desde_perfil(perfil)
    assert "Adaptar actividades a sensibilidades y estimulos aversivos." in objs

def test_objetivos_desde_perfil_intereses():
    perfil = {
        "intereses": ["trenes"]
    }
    objs = _objetivos_desde_perfil(perfil)
    assert "Incorporar intereses del nino como motivadores terapeuticos." in objs

def test_objetivos_desde_perfil_default():
    objs = _objetivos_desde_perfil({})
    assert "Fortalecer comunicacion funcional." in objs
    assert "Mejorar tolerancia a actividades guiadas." in objs
