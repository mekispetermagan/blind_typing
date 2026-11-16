import hashlib

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..config import ROOT
from ..database import engine
from ..models import Role, TrainerStudent, User
from ..schemas.progress import StudentProgress
from .progress import progress_for_user

router = APIRouter(prefix='/api/trainer')


def require_trainer(user: User = Depends(current_user)) -> User:
    if user.role not in {Role.TRAINER, Role.ADMIN}:
        raise HTTPException(403, 'Trainer role required')
    return user


def name_audio(user: User):
    digest = hashlib.sha256(user.name.encode('utf-8')).hexdigest()
    return ROOT / 'assets' / 'student_names' / f'{digest}.wav', digest[:16]


def assigned_student(session: Session, trainer_id: int, student_id: int) -> User:
    student = session.scalar(
        select(User).join(TrainerStudent, TrainerStudent.student_id == User.id)
        .where(TrainerStudent.trainer_id == trainer_id,
               User.id == student_id, User.student_active.is_(True))
    )
    if student is None:
        raise HTTPException(404, 'Student not found')
    return student


@router.get('/students')
def students(trainer: User = Depends(require_trainer)):
    with Session(engine) as session:
        users = session.scalars(
            select(User).join(TrainerStudent, TrainerStudent.student_id == User.id)
            .where(TrainerStudent.trainer_id == trainer.id, User.student_active.is_(True))
            .order_by(User.name.collate('NOCASE'), User.id)
        ).all()
        result = []
        for user in users:
            path, revision = name_audio(user)
            result.append({'id': user.id, 'name': user.name,
                           'name_audio_revision': revision if path.is_file() else None})
        return result


@router.get('/students/{student_id}/progress', response_model=StudentProgress)
def student_progress(student_id: int, trainer: User = Depends(require_trainer)):
    with Session(engine) as session:
        return progress_for_user(session, assigned_student(session, trainer.id, student_id))


@router.get('/students/{student_id}/name-audio')
def student_name_audio(student_id: int, request: Request, trainer: User = Depends(require_trainer)):
    with Session(engine) as session:
        path, revision = name_audio(assigned_student(session, trainer.id, student_id))
        if not path.is_file():
            raise HTTPException(404, 'Name recording not found')
        stat = path.stat()
        etag = f'"{revision}-{stat.st_mtime_ns:x}-{stat.st_size:x}"'
        if request.headers.get('if-none-match') == etag:
            return Response(status_code=304, headers={'ETag': etag, 'Cache-Control': 'private, no-cache'})
        return FileResponse(path, headers={'ETag': etag, 'Cache-Control': 'private, no-cache'})
