import tempfile
import unittest
from pathlib import Path

from argon2 import PasswordHasher
from sqlalchemy import create_engine, event, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import ActivityAttempt, AttemptKeyStatistics, AttemptStatus, Role, User
from app.models.base import Base, utc_now


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.engine = create_engine(f'sqlite:///{Path(self.tempdir.name) / "test.db"}')
        self.addCleanup(self.engine.dispose)

        @event.listens_for(self.engine, 'connect')
        def foreign_keys(connection, _record):
            connection.execute('PRAGMA foreign_keys=ON')

        Base.metadata.create_all(self.engine)

    def test_user_and_attempt_statistics(self):
        password = PasswordHasher()
        with Session(self.engine) as session:
            user = User(name='Mekis Péter', role=Role.ADMIN, credential_hash=password.hash('1234'))
            session.add(user)
            session.flush()
            session.add(ActivityAttempt(
                id='attempt-1', user_id=user.id, activity_id='home_row_words',
                activity_type='words', started_at=utc_now(),
                status=AttemptStatus.IN_PROGRESS,
            ))
            session.add(AttemptKeyStatistics(
                attempt_id='attempt-1', key='ö', first_try_correct_count=2,
                first_try_incorrect_count=1,
            ))
            session.commit()
            self.assertTrue(password.verify(user.credential_hash, '1234'))
            self.assertNotEqual(user.credential_hash, '1234')
            self.assertEqual(session.scalar(select(User)).role, Role.ADMIN)
            session.add(AttemptKeyStatistics(
                attempt_id='attempt-1', key='ö', first_try_correct_count=0,
                first_try_incorrect_count=0,
            ))
            with self.assertRaises(IntegrityError):
                session.commit()

    def test_foreign_key_and_nonnegative_constraints(self):
        with Session(self.engine) as session:
            session.add(AttemptKeyStatistics(
                attempt_id='missing', key='a', first_try_correct_count=0,
                first_try_incorrect_count=1,
            ))
            with self.assertRaises(IntegrityError):
                session.commit()
            session.rollback()
            session.add(User(name='Test', role=Role.STUDENT))
            session.flush()
            session.add(ActivityAttempt(
                id='bad', user_id=1, activity_id='test', activity_type='words',
                started_at=utc_now(), status=AttemptStatus.IN_PROGRESS,
                mistake_count=-1,
            ))
            with self.assertRaises(IntegrityError):
                session.commit()


if __name__ == '__main__':
    unittest.main()
