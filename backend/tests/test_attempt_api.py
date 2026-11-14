import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from uuid import uuid4

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from fastapi import HTTPException

from app.models import ActivityAttempt, AttemptKeyStatistics, Role, User
from app.models.base import Base
from app.routers.attempts import save_attempt
from app.schemas.attempt import AttemptSnapshot


class AttemptApiTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = create_engine(f'sqlite:///{Path(self.directory.name) / "test.db"}')
        self.addCleanup(self.engine.dispose)
        Base.metadata.create_all(self.engine)
        with Session(self.engine) as session:
            session.add(User(name='test', role=Role.ADMIN))
            session.commit()
        self.patcher = patch('app.routers.attempts.engine', self.engine)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.id = uuid4()
        self.data = dict(revision=0, activity_id='lesson', activity_type='words',
                         started_at='2026-01-01T10:00:00Z', status='in_progress',
                         active_duration_ms=30, mistake_count=1,
                         keys={'ö': dict(first_try_correct_count=0, first_try_incorrect_count=1)})

    def test_snapshots_are_idempotent_and_stale_updates_do_not_replace_newer(self):
        save_attempt(self.id, AttemptSnapshot(**self.data))
        updated = dict(self.data, revision=2, status='completed',
                       ended_at='2026-01-01T10:01:00Z', mistake_count=2)
        save_attempt(self.id, AttemptSnapshot(**updated))
        save_attempt(self.id, AttemptSnapshot(**self.data))
        with Session(self.engine) as session:
            attempt = session.scalar(select(ActivityAttempt))
            counts = session.scalars(select(AttemptKeyStatistics)).all()
            self.assertEqual(attempt.revision, 2)
            self.assertEqual(attempt.status.value, 'completed')
            self.assertEqual(attempt.mistake_count, 2)
            self.assertEqual(len(counts), 1)
            self.assertEqual(counts[0].key, 'ö')
            self.assertEqual(counts[0].first_try_incorrect_count, 1)

    def test_multiple_users_require_identity_design(self):
        with Session(self.engine) as session:
            session.add(User(name='other', role=Role.STUDENT))
            session.commit()
        with self.assertRaises(HTTPException) as error:
            save_attempt(self.id, AttemptSnapshot(**self.data))
        self.assertEqual(error.exception.status_code, 409)


if __name__ == '__main__':
    unittest.main()
