import os
from typing import BinaryIO
import uuid

from app.application.ports.file_storage import IFileStorage


class CloudStorageAdapter(IFileStorage):
    def __init__(self):
        self.upload_dir = os.getenv(
            "RIMAI_UPLOAD_DIR",
            os.path.abspath(
                os.path.join(
                    os.path.dirname(__file__),
                    "../../../../uploads/evaluations",
                )
            ),
        )
        os.makedirs(self.upload_dir, exist_ok=True)

    def upload_file(
        self,
        file_stream: BinaryIO,
        filename: str,
        content_type: str,
    ) -> str:
        safe_name = os.path.basename(filename).replace(" ", "_")
        unique_name = f"{uuid.uuid4()}_{safe_name}"
        target = os.path.join(self.upload_dir, unique_name)
        with open(target, "wb") as out:
            while True:
                chunk = file_stream.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
        return f"/api/files/evaluations/{unique_name}"
