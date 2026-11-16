import json
import re
from threading import Lock
from datetime import datetime, timedelta, timezone
from math import floor
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..config import DATABASE_PATH
from ..database import engine
from ..homework_audio import audio_for, resolve_asset, targets
from ..models import ActivityAttempt, AttemptKeyStatistics, AttemptStatus, Homework, HomeworkAttempt, HomeworkDeadline, HomeworkEntry, User
from ..models.base import utc_now
from ..schemas.attempt import AttemptSnapshot
from .attempts import utc_naive
from .trainer import assigned_student, name_audio, require_trainer

router = APIRouter(prefix='/api')
_create_lock = Lock()


class EntryInput(BaseModel):
    text: str = Field(min_length=1)
    repetitions: int = Field(ge=1)

    @field_validator('text')
    @classmethod
    def valid_text(cls, value):
        if not targets(value):
            raise ValueError('Entry must contain at least one letter or digit')
        return value.strip()


class HomeworkInput(BaseModel):
    id: str | None = Field(default=None, pattern=r'^[0-9a-f]{32}$')
    deadline: datetime
    entries: list[EntryInput] = Field(min_length=1)


class DeadlineInput(BaseModel):
    deadline: datetime


def deadline_value(value: datetime) -> datetime:
    deadline = utc_naive(value)
    if deadline < utc_now() + timedelta(minutes=60):
        raise HTTPException(422, 'Deadline must be at least 60 minutes in the future')
    return deadline


def aware(value):
    return value.replace(tzinfo=timezone.utc) if value else None


def authorized(session: Session, homework_id: str, user: User) -> Homework:
    hw = session.get(Homework, homework_id)
    if hw is None:
        raise HTTPException(404, 'Homework not found')
    if hw.student_id != user.id:
        require_trainer(user)
        assigned_student(session, user.id, hw.student_id)
    return hw


def entries_for(session, hw_id):
    return session.scalars(select(HomeworkEntry).where(HomeworkEntry.homework_id == hw_id).order_by(HomeworkEntry.position)).all()


def completed_for(session, hw_id):
    return session.execute(
        select(ActivityAttempt, HomeworkAttempt).join(HomeworkAttempt, HomeworkAttempt.attempt_id == ActivityAttempt.id)
        .where(HomeworkAttempt.homework_id == hw_id, HomeworkAttempt.submitted_at.is_not(None),
               ActivityAttempt.status == AttemptStatus.COMPLETED)
        .order_by(HomeworkAttempt.submitted_at.desc(), ActivityAttempt.id.desc())
    ).all()


def attempt_detail(session, attempt, link):
    keys = session.scalars(select(AttemptKeyStatistics).where(AttemptKeyStatistics.attempt_id == attempt.id).order_by(AttemptKeyStatistics.key)).all()
    return {'id': attempt.id, 'submitted_at': aware(link.submitted_at), 'active_duration_ms': attempt.active_duration_ms,
            'mistake_count': attempt.mistake_count, 'score': attempt.score,
            'keys': [{'key': x.key, 'correct': x.first_try_correct_count, 'incorrect': x.first_try_incorrect_count} for x in keys]}


def homework_detail(session, hw, *, include_attempts=False):
    trainer = session.get(User, hw.trainer_id)
    submissions = completed_for(session, hw.id)
    name_path, name_revision = name_audio(trainer)
    result = {'id': hw.id, 'trainer_id': hw.trainer_id, 'trainer_name': trainer.name,
              'trainer_audio_revision': name_revision if name_path.is_file() else None,
              'student_id': hw.student_id, 'created_at': aware(hw.created_at), 'deadline': aware(hw.deadline),
              'expired': utc_now() >= hw.deadline, 'submitted': bool(submissions),
              'entries': [{'text': e.text, 'repetitions': e.repetitions,
                           'audio': resolve_asset(hw.id, json.loads(e.audio)['sentence'])}
                          for e in entries_for(session, hw.id)]}
    if include_attempts:
        result['attempts'] = [attempt_detail(session, a, l) for a, l in submissions]
    return result


@router.post('/trainer/students/{student_id}/homeworks')
def create_homework(student_id: int, data: HomeworkInput, trainer: User = Depends(require_trainer)):
    with _create_lock:
        return _create_homework(student_id, data, trainer)


def _create_homework(student_id: int, data: HomeworkInput, trainer: User):
    hw_id = data.id or uuid4().hex
    with Session(engine) as session:
        assigned_student(session, trainer.id, student_id)
        existing = session.get(Homework, hw_id)
        if existing is not None:
            previous = entries_for(session, hw_id)
            same = (existing.trainer_id == trainer.id and existing.student_id == student_id
                    and existing.deadline == utc_naive(data.deadline)
                    and [(x.text, x.repetitions) for x in previous] == [(x.text, x.repetitions) for x in data.entries])
            if not same:
                raise HTTPException(409, 'Homework request conflict')
            return homework_detail(session, existing)
    deadline = deadline_value(data.deadline)
    try:
        prepared = [(entry, {'sentence': audio_for(entry.text), 'words': [audio_for(word) for word in targets(entry.text)]}) for entry in data.entries]
    except Exception as error:
        raise HTTPException(503, 'Could not generate homework speech') from error
    with Session(engine) as session, session.begin():
        assigned_student(session, trainer.id, student_id)
        created_at = utc_now()
        hw = Homework(id=hw_id, trainer_id=trainer.id, student_id=student_id, created_at=created_at, deadline=deadline)
        session.add(hw)
        session.flush()
        session.add(HomeworkDeadline(homework_id=hw_id, effective_at=created_at, deadline=deadline))
        session.add_all(HomeworkEntry(homework_id=hw_id, position=i, text=entry.text,
                                     repetitions=entry.repetitions, audio=json.dumps(audio, ensure_ascii=False))
                        for i, (entry, audio) in enumerate(prepared))
        session.flush()
        return homework_detail(session, hw)


@router.post('/trainer/homeworks/{homework_id}/reopen')
def reopen_homework(homework_id: str, data: DeadlineInput, trainer: User = Depends(require_trainer)):
    deadline = deadline_value(data.deadline)
    with Session(engine) as session, session.begin():
        hw = authorized(session, homework_id, trainer)
        if hw.trainer_id != trainer.id:
            raise HTTPException(404, 'Homework not found')
        if utc_now() < hw.deadline:
            raise HTTPException(409, 'Only expired homework can be reopened')
        hw.deadline = deadline
        session.add(HomeworkDeadline(homework_id=hw.id, effective_at=utc_now(), deadline=deadline))
        session.flush()
        return homework_detail(session, hw)


@router.get('/homeworks')
def student_homeworks(user: User = Depends(current_user)):
    now = utc_now()
    with Session(engine) as session:
        rows = session.scalars(select(Homework).where(Homework.student_id == user.id, Homework.deadline >= now - timedelta(days=7))).all()
        result = [homework_detail(session, hw) for hw in rows]
        return sorted(result, key=lambda x: (x['expired'], x['submitted'], x['deadline'], x['id']))


@router.get('/trainer/students/{student_id}/homeworks')
def trainer_homeworks(student_id: int, trainer: User = Depends(require_trainer)):
    now = utc_now()
    with Session(engine) as session:
        assigned_student(session, trainer.id, student_id)
        rows = session.scalars(select(Homework).where(Homework.trainer_id == trainer.id, Homework.student_id == student_id)).all()
        result = [homework_detail(session, hw, include_attempts=True) for hw in rows]
        result = [hw for hw in result if hw['submitted'] or not hw['expired'] or hw['deadline'].replace(tzinfo=None) >= now - timedelta(days=7)]
        return sorted(result, key=lambda x: (x['expired'], x['submitted'], x['deadline'], x['id']))


@router.get('/homeworks/{homework_id}')
def get_homework(homework_id: str, user: User = Depends(current_user)):
    with Session(engine) as session:
        hw = authorized(session, homework_id, user)
        info = homework_detail(session, hw, include_attempts=True)
        units = []
        for entry in entries_for(session, hw.id):
            audio = json.loads(entry.audio)
            for repetition in range(entry.repetitions):
                units.append({'id': f'hw_{hw.id}_{entry.position}_{repetition}', 'text': entry.text,
                              'sentenceAudio': resolve_asset(hw.id, audio['sentence']), 'wordAudio': [resolve_asset(hw.id, x) for x in audio['words']]})
        info['exercise'] = {'id': f'homework_{hw.id}', 'title': 'Házi feladat', 'type': 'homework',
                            'baselineSeconds': 7.5 * len(units), 'units': units}
        return info


@router.get('/homeworks/{homework_id}/trainer-audio')
def homework_trainer_audio(homework_id: str, user: User = Depends(current_user)):
    with Session(engine) as session:
        hw = authorized(session, homework_id, user)
        path, _ = name_audio(session.get(User, hw.trainer_id))
        if not path.is_file():
            raise HTTPException(404)
        return FileResponse(path, headers={'Cache-Control': 'private, no-cache'})


@router.get('/homeworks/{homework_id}/audio/{digest}')
def homework_audio(homework_id: str, digest: str, request: Request, user: User = Depends(current_user)):
    if not re.fullmatch(r'[0-9a-f]{64}', digest):
        raise HTTPException(404)
    with Session(engine) as session:
        authorized(session, homework_id, user)
        allowed = any(f'pool:{digest}' in json.dumps(json.loads(e.audio)) for e in entries_for(session, homework_id))
        path = DATABASE_PATH.parent / 'homework_audio' / f'{digest}.wav'
        if not allowed or not path.is_file():
            raise HTTPException(404)
        stat = path.stat()
        etag = f'\"{digest}-{stat.st_mtime_ns:x}-{stat.st_size:x}\"'
        headers = {'ETag': etag, 'Cache-Control': 'private, no-cache'}
        if request.headers.get('if-none-match') == etag:
            return Response(status_code=304, headers=headers)
        return FileResponse(path, headers=headers)


class HomeworkSnapshot(AttemptSnapshot):
    activity_type: str


@router.put('/homeworks/{homework_id}/attempts/{attempt_id}')
def save_homework_attempt(homework_id: str, attempt_id: UUID, request: Request, snapshot: HomeworkSnapshot, user: User = Depends(current_user)):
    received_at = getattr(request.state, 'submission_received_at', None) or utc_now()
    with Session(engine) as session, session.begin():
        hw = session.get(Homework, homework_id)
        if hw is None or hw.student_id != user.id:
            raise HTTPException(404, 'Homework not found')
        key = str(attempt_id)
        existing = session.get(ActivityAttempt, key)
        link = session.get(HomeworkAttempt, key)
        if existing is not None and (link is None or link.homework_id != hw.id or existing.user_id != user.id):
            raise HTTPException(409, 'Attempt conflict')
        if existing is not None and existing.status == AttemptStatus.COMPLETED:
            return {'saved': True, 'submitted': True}
        effective_deadline = session.scalar(select(HomeworkDeadline).where(
            HomeworkDeadline.homework_id == hw.id, HomeworkDeadline.effective_at <= received_at
        ).order_by(HomeworkDeadline.effective_at.desc(), HomeworkDeadline.id.desc()).limit(1))
        if effective_deadline is None:
            raise HTTPException(409, 'Attempt predates assignment')
        if snapshot.status == 'completed' and received_at >= effective_deadline.deadline:
            raise HTTPException(409, 'deadline_expired')
        if existing is not None and snapshot.revision <= existing.revision:
            return {'saved': True, 'submitted': False}
        if snapshot.activity_id != f'homework_{hw.id}' or snapshot.activity_type != 'homework':
            raise HTTPException(422, 'Invalid homework attempt')
        started = utc_naive(snapshot.started_at)
        ended = utc_naive(snapshot.ended_at)
        if existing is None:
            existing = ActivityAttempt(id=key, user_id=user.id, activity_id=f'homework_{hw.id}',
                                       activity_type='homework', started_at=started, status=AttemptStatus(snapshot.status))
            session.add(existing)
            session.flush()
            link = HomeworkAttempt(attempt_id=key, homework_id=hw.id)
            session.add(link)
        existing.revision = snapshot.revision
        existing.status = AttemptStatus(snapshot.status)
        existing.ended_at = received_at if snapshot.status == 'completed' else ended
        existing.active_duration_ms = snapshot.active_duration_ms
        existing.mistake_count = snapshot.mistake_count
        existing.mode = snapshot.mode
        existing.mode_changed = snapshot.mode_changed
        if snapshot.status == 'completed':
            baseline = 7.5 * sum(entry.repetitions for entry in entries_for(session, hw.id))
            existing.score = floor(100 * baseline / max(1, snapshot.active_duration_ms // 1000) * 0.95 ** (snapshot.mistake_count - 10) + .5)
            link.submitted_at = received_at
        session.query(AttemptKeyStatistics).filter_by(attempt_id=key).delete()
        session.add_all(AttemptKeyStatistics(attempt_id=key, key=key_name, **count.model_dump()) for key_name, count in snapshot.keys.items())
        return {'saved': True, 'submitted': snapshot.status == 'completed'}
