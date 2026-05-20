from abc import ABC, abstractmethod
from typing import BinaryIO

class IFileStorage(ABC):
    @abstractmethod
    def upload_file(self, file_stream: BinaryIO, filename: str, content_type: str) -> str:
        """ Uploads a file and returns the public URL """
        pass
