from datetime import datetime
from enum import Enum

from sqlalchemy import Boolean, CheckConstraint, DateTime, Enum as SqlEnum, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class AttemptStatus(str, Enum):
    IN_PROGRESS = 'in_progress'
    COMPLETED = 'completed'
    INTERRUPTED = 'interrupted'


class ActivityAttempt(Base):
    __tablename__ = 'activity_attempts'
    __table_args__ = (
        CheckConstraint('active_duration_ms >= 0', name='nonnegative_duration'),
        CheckConstraint('mistake_count >= 0', name='nonnegative_mistakes'),
        CheckConstraint('score IS NULL OR score >= 0', name='nonnegative_score'),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), nullable=False, index=True)
    activity_id: Mapped[str] = mapped_column(String, nullable=False, index=True)
    activity_type: Mapped[str] = mapped_column(String, nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    status: Mapped[AttemptStatus] = mapped_column(
        SqlEnum(AttemptStatus, values_callable=lambda statuses: [status.value for status in statuses],
                native_enum=False, create_constraint=True, name='attempt_status'),
        nullable=False,
    )
    active_duration_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    mistake_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    mode: Mapped[str | None] = mapped_column(String, nullable=True)
    mode_changed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    content_version: Mapped[str | None] = mapped_column(String, nullable=True)
    scoring_version: Mapped[str | None] = mapped_column(String, nullable=True)


class AttemptKeyStatistics(Base):
    __tablename__ = 'attempt_key_statistics'
    __table_args__ = (
        UniqueConstraint('attempt_id', 'key', name='unique_attempt_key'),
        CheckConstraint('first_try_correct_count >= 0', name='nonnegative_first_try_correct'),
        CheckConstraint('first_try_incorrect_count >= 0', name='nonnegative_first_try_incorrect'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    attempt_id: Mapped[str] = mapped_column(
        ForeignKey('activity_attempts.id', ondelete='CASCADE'), nullable=False, index=True,
    )
    key: Mapped[str] = mapped_column(String, nullable=False)
    first_try_correct_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    first_try_incorrect_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
