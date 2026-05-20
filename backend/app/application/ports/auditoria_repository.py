from abc import ABC, abstractmethod
from app.domain.entities.log_trazabilidad import LogTrazabilidad

class IAuditoriaRepository(ABC):
    @abstractmethod
    def log_action(self, log: LogTrazabilidad) -> LogTrazabilidad:
        pass
