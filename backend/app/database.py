from sqlalchemy import create_engine, event

from .config import DATABASE_PATH
from . import models  # Register models with Base.metadata.
from .models.base import Base


engine = create_engine(f'sqlite:///{DATABASE_PATH}')


@event.listens_for(engine, 'connect')
def enable_foreign_keys(connection, _record):
    cursor = connection.cursor()
    cursor.execute('PRAGMA foreign_keys=ON')
    cursor.close()


def initialize_database():
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(engine)
    # Upgrade the development database created before snapshots had revisions.
    with engine.begin() as connection:
        columns = connection.exec_driver_sql('PRAGMA table_info(activity_attempts)').fetchall()
        if not any(column[1] == 'revision' for column in columns):
            connection.exec_driver_sql('ALTER TABLE activity_attempts ADD COLUMN revision INTEGER NOT NULL DEFAULT 0')
