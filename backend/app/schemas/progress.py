from datetime import datetime
from pydantic import BaseModel, Field


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
    score: int | None = None
    title_audio: list[str] = Field(default_factory=list)
    keys: list[KeyProgress]


class StudentProgress(BaseModel):
    name: str
    attempts: list[ProgressAttempt]
