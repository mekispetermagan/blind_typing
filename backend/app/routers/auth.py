from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel
from sqlalchemy import delete, insert, literal, select, update
from sqlalchemy.orm import Session

from ..auth import authenticated_user, bearer, hasher, new_token, token_hash, valid_pin, verify_pin
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
        if (user is None or not user.credential_hash or not valid_pin(data.pin, user.role)
                or not verify_pin(user.credential_hash, data.pin)):
            raise HTTPException(401, 'Invalid credentials')
        token = new_token()
        # A concurrent PIN change must not let an old credential issue a new token.
        credential = select(literal(token_hash(token)), User.id, literal(utc_now())).where(
            User.id == user.id, User.credential_hash == user.credential_hash, User.role == user.role,
        )
        created = session.execute(insert(AuthSession).from_select(
            ['token_hash', 'user_id', 'last_activity'], credential,
        ))
        if created.rowcount != 1:
            raise HTTPException(401, 'Invalid credentials')
        response = {'token': token, 'user_id': user.id, 'name': user.name, 'role': user.role.value,
                    'pin_temporary': user.pin_temporary}
        session.commit()
        return response


class PinUpdate(BaseModel):
    new_pin: str
    current_pin: str | None = None


@router.post('/pin')
def set_pin(data: PinUpdate, user: User = Depends(authenticated_user),
            credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    if not valid_pin(data.new_pin, user.role):
        raise HTTPException(422, 'Invalid new PIN')
    if data.current_pin is not None:
        if (not user.credential_hash or not valid_pin(data.current_pin, user.role)
                or not verify_pin(user.credential_hash, data.current_pin)):
            raise HTTPException(400, 'Incorrect current PIN')
    elif not user.pin_temporary:
        # A first-login request can be retried after a lost success response.
        if user.credential_hash and verify_pin(user.credential_hash, data.new_pin):
            return {'ok': True}
        raise HTTPException(409, 'PIN setup already completed')

    active_token = token_hash(credentials.credentials)
    replacement = hasher.hash(data.new_pin)
    with Session(engine) as session:
        active_session = select(AuthSession.token_hash).where(
            AuthSession.token_hash == active_token, AuthSession.user_id == user.id,
        ).exists()
        saved = session.execute(update(User).where(
            User.id == user.id, User.credential_hash == user.credential_hash,
            User.pin_temporary == user.pin_temporary, User.role == user.role, active_session,
        ).values(credential_hash=replacement, pin_temporary=False))
        if saved.rowcount != 1:
            raise HTTPException(409, 'PIN or session changed')
        session.execute(delete(AuthSession).where(
            AuthSession.user_id == user.id, AuthSession.token_hash != active_token,
        ))
        session.commit()
    return {'ok': True}


class Interaction(BaseModel):
    occurred_at: datetime


@router.post('/activity')
def activity(data: Interaction, user: User = Depends(authenticated_user), credentials: HTTPAuthorizationCredentials = Depends(bearer)):
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
def logout(user: User = Depends(authenticated_user), credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    with Session(engine) as session:
        auth = session.get(AuthSession, token_hash(credentials.credentials))
        if auth is not None:
            session.delete(auth)
            session.commit()
    return {'ok': True}
