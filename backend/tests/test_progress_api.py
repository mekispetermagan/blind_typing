import unittest
from datetime import datetime
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.models import ActivityAttempt, AttemptKeyStatistics, AttemptStatus, Role, User
from app.models.base import Base
from app.routers.progress import student_progress


class ProgressApiTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = create_engine(f'sqlite:///{Path(self.directory.name) / "test.db"}')
        self.addCleanup(self.engine.dispose)
        Base.metadata.create_all(self.engine)
        self.patcher = patch('app.routers.progress.engine', self.engine)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        with Session(self.engine) as session:
            session.add(User(name='Test', role=Role.STUDENT))
            session.flush()
            for index, status in enumerate((AttemptStatus.COMPLETED, AttemptStatus.INTERRUPTED, AttemptStatus.IN_PROGRESS)):
                session.add(ActivityAttempt(id=str(index), user_id=1, activity_id='reach_ou_o_words',
                    activity_type='words', started_at=datetime(2026, 5, index + 1), status=status,
                    active_duration_ms=1000, mistake_count=index))
                session.add(AttemptKeyStatistics(attempt_id=str(index), key='ö',
                    first_try_correct_count=3, first_try_incorrect_count=1))
            session.commit()

    def test_only_finished_attempts_and_correct_counts_returned(self):
        progress = student_progress()
        self.assertEqual(progress.name, 'Test')
        self.assertEqual([a.status for a in progress.attempts], ['interrupted', 'completed'])
        self.assertEqual(progress.attempts[0].keys[0].correct, 3)
        self.assertEqual(progress.attempts[0].keys[0].incorrect, 1)
        self.assertIsNotNone(progress.attempts[0].started_at.tzinfo)
        self.assertNotEqual(progress.attempts[0].title, 'reach_ou_o_words')

    def test_does_not_guess_user_when_multiple_exist(self):
        with Session(self.engine) as session:
            session.add(User(name='Other', role=Role.STUDENT))
            session.commit()
        with self.assertRaises(HTTPException) as error:
            student_progress()
        self.assertEqual(error.exception.status_code, 409)
