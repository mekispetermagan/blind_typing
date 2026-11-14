from datetime import datetime
from pydantic import BaseModel


class KeyProgress(BaseModel):
    key: str
    correct: int
    incorrect: int


class ProgressAttempt(BaseModel):
    activity_id: str
    title: str
    started_at: datetime
    status: str
    active_duration_ms: int
    mistake_count: int
    keys: list[KeyProgress]


class StudentProgress(BaseModel):
    name: str
    attempts: list[ProgressAttempt]
