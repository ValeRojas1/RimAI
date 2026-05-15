from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

hash1 = "$2b$12$LK1Jv5DGrlf0Lz8nWz7bMO.l0b4c2i6P5Rb5yT8bL4YKb.Eq1Ev2"
print(pwd_context.verify("Rimai2024!", hash1))
