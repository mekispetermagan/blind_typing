import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import database
from app.auth import hasher, token_hash
from app.main import app
from app.models import ActivityAttempt, AttemptStatus, AuthSession, Role, TrainerStudent, User
from app.models.base import utc_now


class AuthApiTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = create_engine(f'sqlite:///{Path(self.directory.name) / "test.db"}')
        self.addCleanup(self.engine.dispose)

        @event.listens_for(self.engine, 'connect')
        def foreign_keys(connection, _record):
            connection.execute('PRAGMA foreign_keys=ON')

        for target in ['app.database.engine', 'app.auth.engine', 'app.routers.auth.engine',
                       'app.routers.progress.engine', 'app.routers.attempts.engine', 'app.routers.trainer.engine']:
            patcher = patch(target, self.engine)
            patcher.start()
            self.addCleanup(patcher.stop)
        database.initialize_database()
        with Session(self.engine) as session:
            session.add_all([
                User(name='Admin', identifier='Admin@example.org', role=Role.ADMIN, credential_hash=hasher.hash('123456')),
                User(name='Student', identifier='xyz', role=Role.STUDENT, credential_hash=hasher.hash('1234')),
                User(name='Trainer', identifier='trainer', role=Role.TRAINER, credential_hash=hasher.hash('123456')),
            ])
            session.commit()
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def login(self, identifier, pin):
        return self.client.post('/api/auth/login', json={'identifier': identifier, 'pin': pin})

    def test_login_and_authenticated_content(self):
        self.assertEqual(self.client.get('/api/menu').status_code, 401)
        self.assertEqual(self.login('xyz', '123456').status_code, 401)
        self.assertEqual(self.login('xyz', 'wrong').status_code, 401)
        response = self.login(' ADMIN@EXAMPLE.ORG ', '123456')
        self.assertEqual(response.status_code, 200)
        token = response.json()['token']
        headers = {'Authorization': f'Bearer {token}'}
        self.assertEqual(self.client.get('/api/menu', headers=headers).status_code, 200)
        self.assertEqual(self.client.get('/api/progress', headers=headers).json()['name'], 'Admin')
        self.assertEqual(self.client.post('/api/auth/logout', headers=headers).status_code, 200)
        self.assertEqual(self.client.get('/api/menu', headers=headers).status_code, 401)
        self.assertEqual(self.login('xyz', '1234').status_code, 200)

    def test_area_permissions_and_menu_options(self):
        self.assertEqual(self.client.get('/api/areas/admin/menu').status_code, 401)
        for identifier, pin, statuses in [
            ('admin@example.org', '123456', (200, 200, 200)),
            ('trainer', '123456', (403, 200, 200)),
            ('xyz', '1234', (403, 403, 200)),
        ]:
            token = self.login(identifier, pin).json()['token']
            headers = {'Authorization': f'Bearer {token}'}
            for area, status in zip(('admin', 'trainer', 'student'), statuses):
                response = self.client.get(f'/api/areas/{area}/menu', headers=headers)
                self.assertEqual(response.status_code, status, (identifier, area))
                if status != 200:
                    continue
                children = response.json()['root']['children']
                commands = [child.get('command') for child in children]
                self.assertEqual(commands[-1], 'logout')
                if area != 'student':
                    expected = ['addHomework', 'viewHomeworks', 'students', 'areaSelector', 'logout'] if area == 'trainer' else ['areaSelector', 'logout']
                    self.assertEqual(commands, expected)
                else:
                    self.assertEqual('areaSelector' in commands, identifier != 'xyz')
            self.assertEqual(self.client.get('/api/areas/unknown/menu', headers=headers).status_code, 404)

    def test_trainer_only_sees_assigned_student_progress_and_recordings(self):
        with Session(self.engine) as session:
            session.add_all([TrainerStudent(trainer_id=3, student_id=1),
                             TrainerStudent(trainer_id=3, student_id=2),
                             ActivityAttempt(id='admin-attempt', user_id=1, activity_id='lesson', activity_type='words',
                                 started_at=datetime(2026, 1, 1), status=AttemptStatus.COMPLETED),
                             ActivityAttempt(id='student-attempt', user_id=2, activity_id='other', activity_type='words',
                                 started_at=datetime(2026, 1, 2), status=AttemptStatus.COMPLETED)])
            session.commit()
        trainer = self.login('trainer', '123456').json()['token']
        admin = self.login('admin@example.org', '123456').json()['token']
        student = self.login('xyz', '1234').json()['token']
        headers = lambda token: {'Authorization': f'Bearer {token}'}
        self.assertEqual(self.client.get('/api/trainer/students').status_code, 401)
        self.assertEqual(self.client.get('/api/trainer/students', headers=headers(student)).status_code, 403)
        self.assertEqual(self.client.get('/api/trainer/students', headers=headers(admin)).json(), [])
        response = self.client.get('/api/trainer/students', headers=headers(trainer))
        self.assertEqual([item['id'] for item in response.json()], [1, 2])
        progress = self.client.get('/api/trainer/students/1/progress', headers=headers(trainer)).json()
        self.assertEqual(progress['name'], 'Admin')
        self.assertEqual([attempt['activity_id'] for attempt in progress['attempts']], ['lesson'])
        self.assertEqual(self.client.get('/api/trainer/students/1/progress', headers=headers(admin)).status_code, 404)
        self.assertEqual(self.client.get('/api/trainer/students/1/progress', headers=headers(student)).status_code, 403)
        recording = Path(self.directory.name) / 'name.wav'
        recording.write_bytes(b'demo-audio')
        with patch('app.routers.trainer.name_audio', return_value=(recording, '1234567890abcdef')):
            audio = self.client.get('/api/trainer/students/1/name-audio', headers=headers(trainer))
            self.assertEqual(audio.content, b'demo-audio')
            self.assertEqual(self.client.get('/api/trainer/students/1/name-audio', headers=headers(admin)).status_code, 404)
            self.assertEqual(self.client.get('/api/trainer/students/1/name-audio', headers={**headers(trainer), 'If-None-Match': audio.headers['etag']}).status_code, 304)
        with Session(self.engine) as session:
            session.get(User, 2).student_active = False
            session.commit()
        self.assertEqual([item['id'] for item in self.client.get('/api/trainer/students', headers=headers(trainer)).json()], [1])
        self.assertEqual(self.client.get('/api/trainer/students/2/progress', headers=headers(trainer)).status_code, 404)
        with Session(self.engine) as session:
            session.delete(session.get(TrainerStudent, (3, 1)))
            session.commit()
        self.assertEqual(self.client.get('/api/trainer/students/1/progress', headers=headers(trainer)).status_code, 404)
        self.assertEqual(self.client.get('/api/trainer/students/1/name-audio', headers=headers(trainer)).status_code, 404)

    def test_role_change_applies_to_existing_token(self):
        token = self.login('trainer', '123456').json()['token']
        headers = {'Authorization': f'Bearer {token}'}
        self.assertEqual(self.client.get('/api/areas/trainer/menu', headers=headers).status_code, 200)
        with Session(self.engine) as session:
            session.get(User, 3).role = Role.STUDENT
            session.commit()
        self.assertEqual(self.client.get('/api/areas/trainer/menu', headers=headers).status_code, 403)
        self.assertEqual(self.client.get('/api/areas/student/menu', headers=headers).status_code, 200)

    def test_only_activity_extends_session(self):
        token = self.login('xyz', '1234').json()['token']
        headers = {'Authorization': f'Bearer {token}'}
        old = utc_now() - timedelta(minutes=9)
        with Session(self.engine) as session:
            auth = session.get(AuthSession, token_hash(token))
            auth.last_activity = old
            session.commit()
        self.assertEqual(self.client.get('/api/menu', headers=headers).status_code, 200)
        with Session(self.engine) as session:
            self.assertEqual(session.get(AuthSession, token_hash(token)).last_activity, old)
        self.assertEqual(self.client.post('/api/auth/activity', headers=headers, json={'occurred_at': utc_now().isoformat() + 'Z'}).status_code, 200)
        with Session(self.engine) as session:
            auth = session.get(AuthSession, token_hash(token))
            self.assertGreater(auth.last_activity, old)
            auth.last_activity = utc_now() - timedelta(minutes=10)
            session.commit()
        self.assertEqual(self.client.post('/api/auth/activity', headers=headers, json={'occurred_at': utc_now().isoformat() + 'Z'}).status_code, 401)

    def test_student_deactivation_removes_assignment_and_keeps_login(self):
        with Session(self.engine) as session:
            session.add(TrainerStudent(trainer_id=1, student_id=2))
            session.commit()
            session.get(User, 2).student_active = False
            session.commit()
            self.assertEqual(session.scalars(select(TrainerStudent)).all(), [])
            session.add(TrainerStudent(trainer_id=1, student_id=2))
            with self.assertRaises(IntegrityError):
                session.commit()
        self.assertEqual(self.login('xyz', '1234').status_code, 200)

    def test_trainer_role_is_required(self):
        with Session(self.engine) as session:
            session.add(TrainerStudent(trainer_id=2, student_id=1))
            with self.assertRaises(IntegrityError):
                session.commit()


if __name__ == '__main__':
    unittest.main()
