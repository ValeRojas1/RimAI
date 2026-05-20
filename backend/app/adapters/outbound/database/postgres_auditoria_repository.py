from app.application.ports.auditoria_repository import IAuditoriaRepository
from app.domain.entities.log_trazabilidad import LogTrazabilidad

class PostgresAuditoriaRepository(IAuditoriaRepository):
    def __init__(self):
        self.logs = []
        self.next_id = 1

    def log_action(self, log: LogTrazabilidad) -> LogTrazabilidad:
        log.id = self.next_id
        self.next_id += 1
        self.logs.append(log)
        # En prod: session.add(LogTrazabilidadModel(...))
        return log
