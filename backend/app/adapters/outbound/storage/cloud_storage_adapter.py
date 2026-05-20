from typing import BinaryIO
import uuid
from app.application.ports.file_storage import IFileStorage

class CloudStorageAdapter(IFileStorage):
    def __init__(self):
        # En una impl real, aquí configuraríamos boto3 (S3) o firebase-admin
        pass

    def upload_file(self, file_stream: BinaryIO, filename: str, content_type: str) -> str:
        # Mock implementation: generamos un URL falso
        unique_name = f"{uuid.uuid4()}_{filename}"
        mock_url = f"https://storage.rimai.com/evaluations/{unique_name}"
        return mock_url
