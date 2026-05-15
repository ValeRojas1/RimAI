from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
hash_real = pwd_context.hash("Rimai2024!")
print(hash_real)
