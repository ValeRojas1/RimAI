from app.database import SessionLocal
from app.models import Nino, Usuario, PadreTutor

db = SessionLocal()
ninos = db.query(Nino).all()
print("Niños totales:", len(ninos))
for n in ninos:
    print(f"ID: {n.id}, Nombre: {n.nombre}, Estado: {n.estado_clinico.value if n.estado_clinico else 'None'}, Activo: {n.activo}, Creado: {n.created_at}")
