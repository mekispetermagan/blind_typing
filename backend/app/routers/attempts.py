from datetime import timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.dialects.sqlite import insert
from sqlalchemy.orm import Session

from ..database import engine
from ..auth import current_user
from ..models import ActivityAttempt, AttemptKeyStatistics, User
from ..schemas.attempt import AttemptSnapshot

router = APIRouter(prefix='/api/attempts')


def utc_naive(value):
    if value is None:
        return None
    if value.tzinfo is None:
        raise HTTPException(422, 'Timestamps must include a UTC offset')
    return value.astimezone(timezone.utc).replace(tzinfo=None)


@router.put('/{attempt_id}')
def save_attempt(attempt_id: UUID, snapshot: AttemptSnapshot, user: User = Depends(current_user)):
    with Session(engine) as session, session.begin():
        values = snapshot.model_dump(exclude={'keys'})
        values['started_at'] = utc_naive(snapshot.started_at)
        values['ended_at'] = utc_naive(snapshot.ended_at)
        values.update(id=str(attempt_id), user_id=user.id)
        statement = insert(ActivityAttempt).values(**values)
        statement = statement.on_conflict_do_update(
            index_elements=['id'],
            set_={key: value for key, value in values.items() if key not in {'id', 'user_id', 'activity_id', 'activity_type', 'started_at'}},
            where=(ActivityAttempt.revision < snapshot.revision)
                  & (ActivityAttempt.user_id == user.id)
                  & (ActivityAttempt.activity_id == snapshot.activity_id)
                  & (ActivityAttempt.activity_type == snapshot.activity_type),
        )
        result = session.execute(statement)
        if result.rowcount:
            session.execute(delete(AttemptKeyStatistics).where(AttemptKeyStatistics.attempt_id == str(attempt_id)))
            session.add_all(AttemptKeyStatistics(attempt_id=str(attempt_id), key=key, **counts.model_dump())
                            for key, counts in snapshot.keys.items())
    return {'saved': True}
