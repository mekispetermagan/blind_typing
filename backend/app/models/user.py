from datetime import datetime
from enum import Enum

from sqlalchemy import Boolean, CheckConstraint, DateTime, Enum as SqlEnum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, validates

from .base import Base, utc_now


class Role(str, Enum):
    ADMIN = 'admin'
    TRAINER = 'trainer'
    STUDENT = 'student'


class User(Base):
    __tablename__ = 'users'

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    identifier: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    role: Mapped[Role] = mapped_column(
        SqlEnum(Role, values_callable=lambda roles: [role.value for role in roles],
                native_enum=False, create_constraint=True, name='user_role'),
        nullable=False,
    )
    credential_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now, nullable=False)
    credential_expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    student_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


    @validates('identifier')
    def normalize_identifier(self, _key, identifier):
        identifier = identifier.strip().casefold()
        if not identifier:
            raise ValueError('Identifier cannot be empty')
        return identifier


class TrainerStudent(Base):
    __tablename__ = 'trainer_students'
    __table_args__ = (CheckConstraint('trainer_id != student_id', name='different_users'),)
    trainer_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)


class AuthSession(Base):
    __tablename__ = 'auth_sessions'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    last_activity: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utc_now)
