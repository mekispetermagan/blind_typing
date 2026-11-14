import json
from datetime import timezone

from fastapi import APIRouter, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import ROOT
from ..database import engine
from ..models import ActivityAttempt, AttemptKeyStatistics, AttemptStatus, User
from ..schemas.progress import KeyProgress, ProgressAttempt, StudentProgress

router = APIRouter(prefix='/api/progress')


def activity_titles():
    titles = {}
    for directory in ('lessons', 'practice'):
        for path in (ROOT / 'data' / directory).glob('*.json'):
            content = json.loads(path.read_text(encoding='utf-8'))
            titles[content['id']] = content['title']
    return titles


@router.get('', response_model=StudentProgress)
def student_progress():
    with Session(engine) as session:
        users = session.scalars(select(User).limit(2)).all()
        if len(users) != 1:
            raise HTTPException(409, 'A single local user is required until authentication is implemented')
        attempts = session.scalars(
            select(ActivityAttempt)
            .where(ActivityAttempt.user_id == users[0].id,
                   ActivityAttempt.status.in_([AttemptStatus.COMPLETED, AttemptStatus.INTERRUPTED]))
            .order_by(ActivityAttempt.started_at.desc(), ActivityAttempt.id.desc())
        ).all()
        key_rows = session.execute(
            select(AttemptKeyStatistics)
            .join(ActivityAttempt, AttemptKeyStatistics.attempt_id == ActivityAttempt.id)
            .where(ActivityAttempt.user_id == users[0].id,
                   ActivityAttempt.status.in_([AttemptStatus.COMPLETED, AttemptStatus.INTERRUPTED]))
        ).scalars()
        keys = {}
        for row in key_rows:
            keys.setdefault(row.attempt_id, []).append(KeyProgress(
                key=row.key, correct=row.first_try_correct_count,
                incorrect=row.first_try_incorrect_count,
            ))
        titles = activity_titles()
        return StudentProgress(name=users[0].name, attempts=[
            ProgressAttempt(
                activity_id=attempt.activity_id,
                title=titles.get(attempt.activity_id, attempt.activity_id),
                started_at=attempt.started_at.replace(tzinfo=timezone.utc),
                status=attempt.status.value,
                active_duration_ms=attempt.active_duration_ms,
                mistake_count=attempt.mistake_count,
                keys=keys.get(attempt.id, []),
            ) for attempt in attempts
        ])
