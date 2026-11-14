from datetime import datetime
from typing import Literal
from pydantic import BaseModel, Field, model_validator


class KeyCounts(BaseModel):
    first_try_correct_count: int = Field(ge=0)
    first_try_incorrect_count: int = Field(ge=0)


class AttemptSnapshot(BaseModel):
    revision: int = Field(ge=0)
    activity_id: str = Field(min_length=1, max_length=200)
    activity_type: Literal['letters', 'words', 'practice']
    started_at: datetime
    ended_at: datetime | None = None
    status: Literal['in_progress', 'completed', 'interrupted']
    active_duration_ms: int = Field(ge=0)
    mistake_count: int = Field(ge=0)
    mode: Literal['simple', 'advanced'] | None = None
    mode_changed: bool = False
    score: int | None = Field(default=None, ge=0)
    keys: dict[str, KeyCounts] = Field(default_factory=dict)

    @model_validator(mode='after')
    def validate_snapshot(self):
        if (self.status == 'in_progress') != (self.ended_at is None):
            raise ValueError('End time must be present exactly for finished attempts')
        if any(len(key) != 1 for key in self.keys):
            raise ValueError('Each key must be a single character')
        return self
