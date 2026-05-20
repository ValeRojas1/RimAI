from abc import ABC, abstractmethod
from typing import Optional
from app.domain.entities.user import User, Therapist

class IUserRepository(ABC):
    @abstractmethod
    def get_by_email(self, email: str) -> Optional[User]:
        pass

    @abstractmethod
    def create_therapist(self, therapist: Therapist) -> Therapist:
        pass

    @abstractmethod
    def create_family_user(self, user: User) -> User:
        pass

    @abstractmethod
    def get_by_id(self, user_id: int) -> Optional[User]:
        pass
