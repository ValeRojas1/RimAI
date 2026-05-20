from typing import BinaryIO
from app.application.ports.patient_repository import IPatientRepository
from app.application.ports.file_storage import IFileStorage
from app.domain.entities.patient import ExternalEvaluation, SourceEnum

class EvaluationUseCases:
    def __init__(self, patient_repo: IPatientRepository, file_storage: IFileStorage):
        self.patient_repo = patient_repo
        self.file_storage = file_storage

    def upload_evaluation(self, patient_id: int, uploaded_by: SourceEnum, file_stream: BinaryIO, filename: str, content_type: str) -> ExternalEvaluation:
        # 1. Upload to storage
        file_url = self.file_storage.upload_file(file_stream, filename, content_type)
        
        # 2. Save in database
        evaluation = ExternalEvaluation(
            patient_id=patient_id,
            file_url=file_url,
            uploaded_by=uploaded_by
        )
        return self.patient_repo.save_external_evaluation(evaluation)
