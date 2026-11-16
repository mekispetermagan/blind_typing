from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, utc_now


class Homework(Base):
    __tablename__ = 'homeworks'
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    trainer_id: Mapped[int] = mapped_column(ForeignKey('users.id'), nullable=False, index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey('users.id'), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utc_now)
    deadline: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


class HomeworkDeadline(Base):
    __tablename__ = 'homework_deadlines'
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    homework_id: Mapped[str] = mapped_column(ForeignKey('homeworks.id', ondelete='CASCADE'), nullable=False, index=True)
    effective_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    deadline: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class HomeworkEntry(Base):
    __tablename__ = 'homework_entries'
    __table_args__ = (CheckConstraint('repetitions > 0', name='positive_repetitions'),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    homework_id: Mapped[str] = mapped_column(ForeignKey('homeworks.id', ondelete='CASCADE'), nullable=False, index=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    repetitions: Mapped[int] = mapped_column(Integer, nullable=False)
    audio: Mapped[str] = mapped_column(Text, nullable=False)


class HomeworkAttempt(Base):
    __tablename__ = 'homework_attempts'
    attempt_id: Mapped[str] = mapped_column(ForeignKey('activity_attempts.id', ondelete='CASCADE'), primary_key=True)
    homework_id: Mapped[str] = mapped_column(ForeignKey('homeworks.id'), nullable=False, index=True)
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
