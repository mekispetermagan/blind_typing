import json
from datetime import timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import ROOT
from ..database import engine
from ..auth import current_user
from ..homework_audio import resolve_asset
from ..models import ActivityAttempt, AttemptKeyStatistics, AttemptStatus, Homework, HomeworkEntry, User
from ..schemas.progress import KeyProgress, ProgressAttempt, StudentProgress

router = APIRouter(prefix='/api/progress')


def activity_titles():
    titles = {}
    for directory in ('lessons', 'practice'):
        for path in (ROOT / 'data' / directory).glob('*.json'):
            content = json.loads(path.read_text(encoding='utf-8'))
            titles[content['id']] = content['title']
    return titles


def progress_for_user(session: Session, user: User) -> StudentProgress:
    attempts = session.scalars(
        select(ActivityAttempt)
        .where(ActivityAttempt.user_id == user.id,
               ActivityAttempt.status.in_([AttemptStatus.COMPLETED, AttemptStatus.INTERRUPTED]))
        .order_by(ActivityAttempt.started_at.desc(), ActivityAttempt.id.desc())
    ).all()
    key_rows = session.execute(
        select(AttemptKeyStatistics)
        .join(ActivityAttempt, AttemptKeyStatistics.attempt_id == ActivityAttempt.id)
        .where(ActivityAttempt.user_id == user.id,
               ActivityAttempt.status.in_([AttemptStatus.COMPLETED, AttemptStatus.INTERRUPTED]))
    ).scalars()
    keys = {}
    for row in key_rows:
        keys.setdefault(row.attempt_id, []).append(KeyProgress(
            key=row.key, correct=row.first_try_correct_count,
            incorrect=row.first_try_incorrect_count,
        ))
    titles = activity_titles()
    homework_audio = {}
    for hw in session.scalars(select(Homework).where(Homework.student_id == user.id)):
        trainer = session.get(User, hw.trainer_id)
        entry = session.scalar(select(HomeworkEntry).where(HomeworkEntry.homework_id == hw.id).order_by(HomeworkEntry.position).limit(1))
        titles[f'homework_{hw.id}'] = f'Házi feladat – {trainer.name}' + (f' – {entry.text}' if entry else '')
        if entry is not None:
            homework_audio[f'homework_{hw.id}'] = ['assets/audio/menu_homeworks.wav', resolve_asset(hw.id, json.loads(entry.audio)['sentence'])]
    return StudentProgress(name=user.name, attempts=[
        ProgressAttempt(
            activity_id=attempt.activity_id,
            title=titles.get(attempt.activity_id, attempt.activity_id),
            started_at=attempt.started_at.replace(tzinfo=timezone.utc),
            status=attempt.status.value,
            active_duration_ms=attempt.active_duration_ms,
            mistake_count=attempt.mistake_count,
            score=attempt.score,
            title_audio=homework_audio.get(attempt.activity_id, []),
            keys=keys.get(attempt.id, []),
        ) for attempt in attempts
    ])

@router.get('', response_model=StudentProgress)
def student_progress(user: User = Depends(current_user)):
    with Session(engine) as session:
        return progress_for_user(session, user)
