from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import bearer, current_user, new_token, token_hash, verify_pin
from ..database import engine
from ..models import AuthSession, User
from ..models.base import utc_now

router = APIRouter(prefix='/api/auth')


class Login(BaseModel):
    identifier: str
    pin: str


@router.post('/login')
def login(data: Login):
    with Session(engine) as session:
        user = session.scalar(select(User).where(User.identifier == data.identifier.strip().casefold()))
        length = 4 if user is not None and user.role.value == 'student' else 6
        if (user is None or not user.credential_hash or not data.pin.isascii()
                or not data.pin.isdigit() or len(data.pin) != length
                or not verify_pin(user.credential_hash, data.pin)):
            raise HTTPException(401, 'Invalid credentials')
        token = new_token()
        session.add(AuthSession(token_hash=token_hash(token), user_id=user.id, last_activity=utc_now()))
        session.commit()
        return {'token': token, 'user_id': user.id, 'name': user.name, 'role': user.role.value}


class Interaction(BaseModel):
    occurred_at: datetime


@router.post('/activity')
def activity(data: Interaction, user: User = Depends(current_user), credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    with Session(engine) as session:
        auth = session.get(AuthSession, token_hash(credentials.credentials))
        if auth is None:
            raise HTTPException(401, 'Session expired')
        if data.occurred_at.tzinfo is None:
            raise HTTPException(422, 'Timestamp must include a UTC offset')
        occurred = data.occurred_at.astimezone(timezone.utc).replace(tzinfo=None)
        auth.last_activity = max(auth.last_activity, min(utc_now(), occurred))
        session.commit()
    return {'ok': True}


@router.post('/logout')
def logout(user: User = Depends(current_user), credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    with Session(engine) as session:
        auth = session.get(AuthSession, token_hash(credentials.credentials))
        if auth is not None:
            session.delete(auth)
            session.commit()
    return {'ok': True}
