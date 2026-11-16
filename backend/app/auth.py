import hashlib
import secrets
from datetime import timedelta

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .database import engine
from .models import AuthSession, User
from .models.base import utc_now

IDLE_LIMIT = timedelta(minutes=10)
hasher = PasswordHasher()
bearer = HTTPBearer(auto_error=False)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_token() -> str:
    return secrets.token_urlsafe(32)


def verify_pin(value: str, pin: str) -> bool:
    try:
        return hasher.verify(value, pin)
    except (InvalidHashError, VerificationError):
        return False


def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> User:
    if credentials is None:
        raise HTTPException(401, 'Authentication required', headers={'WWW-Authenticate': 'Bearer'})
    with Session(engine) as session:
        auth = session.get(AuthSession, token_hash(credentials.credentials))
        if auth is None or utc_now() - auth.last_activity >= IDLE_LIMIT:
            if auth is not None:
                session.delete(auth)
                session.commit()
            raise HTTPException(401, 'Session expired', headers={'WWW-Authenticate': 'Bearer'})
        return session.get(User, auth.user_id)
