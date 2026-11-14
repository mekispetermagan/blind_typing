from datetime import datetime, timezone
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def utc_now() -> datetime:
    # SQLite stores naive datetimes; all application timestamps are UTC.
    return datetime.now(timezone.utc).replace(tzinfo=None)
