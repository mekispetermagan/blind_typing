from sqlalchemy import create_engine, event, inspect

from .config import DATABASE_PATH
from . import models  # Register models with Base.metadata.
from .models.base import Base

engine = create_engine(f'sqlite:///{DATABASE_PATH}')


@event.listens_for(engine, 'connect')
def enable_foreign_keys(connection, _record):
    connection.execute('PRAGMA foreign_keys=ON')


def initialize_database():
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    # Existing development databases predate identifiers and student status.
    with engine.begin() as connection:
        connection.exec_driver_sql('BEGIN IMMEDIATE')
        existing = connection.exec_driver_sql("SELECT name FROM sqlite_master WHERE type='table' AND name='users'").first()
        if existing:
            columns = {column[1] for column in connection.exec_driver_sql('PRAGMA table_info(users)')}
            if 'identifier' not in columns:
                connection.exec_driver_sql('ALTER TABLE users ADD COLUMN identifier VARCHAR')
            if 'student_active' not in columns:
                connection.exec_driver_sql('ALTER TABLE users ADD COLUMN student_active BOOLEAN NOT NULL DEFAULT 1')
            if 'pin_temporary' not in columns:
                connection.exec_driver_sql('ALTER TABLE users ADD COLUMN pin_temporary BOOLEAN NOT NULL DEFAULT 1')
                if inspect(connection).has_table('auth_sessions'):
                    connection.exec_driver_sql('DELETE FROM auth_sessions')
            connection.exec_driver_sql('CREATE UNIQUE INDEX IF NOT EXISTS ix_users_identifier ON users(identifier)')
    Base.metadata.create_all(engine)
    with engine.begin() as connection:
        columns = connection.exec_driver_sql('PRAGMA table_info(activity_attempts)').fetchall()
        if not any(column[1] == 'revision' for column in columns):
            connection.exec_driver_sql('ALTER TABLE activity_attempts ADD COLUMN revision INTEGER NOT NULL DEFAULT 0')
        connection.exec_driver_sql('''CREATE TRIGGER IF NOT EXISTS user_identifier_insert
            BEFORE INSERT ON users WHEN NEW.identifier IS NULL OR length(trim(NEW.identifier))=0
            BEGIN SELECT RAISE(ABORT, 'identifier required'); END''')
        connection.exec_driver_sql('''CREATE TRIGGER IF NOT EXISTS user_identifier_update
            BEFORE UPDATE OF identifier ON users WHEN NEW.identifier IS NULL OR length(trim(NEW.identifier))=0
            BEGIN SELECT RAISE(ABORT, 'identifier required'); END''')
        connection.exec_driver_sql('''CREATE TRIGGER IF NOT EXISTS trainer_student_insert
            BEFORE INSERT ON trainer_students
            WHEN NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.trainer_id AND role IN ('trainer','admin'))
              OR NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.student_id AND student_active=1)
            BEGIN SELECT RAISE(ABORT, 'invalid trainer or inactive student'); END''')
        connection.exec_driver_sql('''CREATE TRIGGER IF NOT EXISTS trainer_student_update
            BEFORE UPDATE ON trainer_students
            WHEN NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.trainer_id AND role IN ('trainer','admin'))
              OR NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.student_id AND student_active=1)
            BEGIN SELECT RAISE(ABORT, 'invalid trainer or inactive student'); END''')
        connection.exec_driver_sql('''CREATE TRIGGER IF NOT EXISTS student_deactivate
            AFTER UPDATE OF student_active ON users WHEN NEW.student_active=0
            BEGIN DELETE FROM trainer_students WHERE student_id=NEW.id; END''')
        connection.exec_driver_sql('''CREATE TRIGGER IF NOT EXISTS trainer_demote
            AFTER UPDATE OF role ON users WHEN NEW.role='student'
            BEGIN DELETE FROM trainer_students WHERE trainer_id=NEW.id; END''')
