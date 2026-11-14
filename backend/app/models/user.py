from datetime import datetime
from enum import Enum

from sqlalchemy import DateTime, Enum as SqlEnum, String
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, utc_now


class Role(str, Enum):
    ADMIN = 'admin'
    TRAINER = 'trainer'
    STUDENT = 'student'


class User(Base):
    __tablename__ = 'users'

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    role: Mapped[Role] = mapped_column(
        SqlEnum(Role, values_callable=lambda roles: [role.value for role in roles],
                native_enum=False, create_constraint=True, name='user_role'),
        nullable=False,
    )
    credential_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now, nullable=False)
    credential_expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
