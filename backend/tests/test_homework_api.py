import tempfile
import unittest
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session
from app import database
from app.auth import hasher
from app.main import app
from app.models import Homework, HomeworkDeadline, Role, TrainerStudent, User
from app.models.base import utc_now

class HomeworkTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = create_engine(f'sqlite:///{Path(self.directory.name) / "db.sqlite"}')
        self.addCleanup(self.engine.dispose)
        @event.listens_for(self.engine, 'connect')
        def foreign_keys(connection, _): connection.execute('PRAGMA foreign_keys=ON')
        for module in ['database', 'auth', 'routers.auth', 'routers.trainer', 'routers.homework', 'routers.progress', 'routers.attempts']:
            p = patch(f'app.{module}.engine', self.engine); p.start(); self.addCleanup(p.stop)
        database.initialize_database()
        with Session(self.engine) as session:
            session.add_all([User(name='Trainer', identifier='trainer', role=Role.TRAINER, credential_hash=hasher.hash('123456')),
                             User(name='Student', identifier='student', role=Role.STUDENT, credential_hash=hasher.hash('1234')),
                             User(name='Other', identifier='other', role=Role.TRAINER, credential_hash=hasher.hash('123456'))])
            session.flush(); session.add_all([TrainerStudent(trainer_id=1, student_id=2), TrainerStudent(trainer_id=3, student_id=2)]); session.commit()
        self.client = TestClient(app); self.addCleanup(self.client.close)
        self.trainer = self.login('trainer', '123456'); self.student = self.login('student', '1234'); self.other = self.login('other', '123456')
        p = patch('app.routers.homework.audio_for', side_effect=lambda text: 'assets/audio/menu_logout.wav'); p.start(); self.addCleanup(p.stop)
    def login(self, identifier, pin):
        result = self.client.post('/api/auth/login', json={'identifier': identifier, 'pin': pin})
        return {'Authorization': 'Bearer ' + result.json()['token']}
    def create(self):
        return self.client.post('/api/trainer/students/2/homeworks', headers=self.trainer, json={'deadline': (utc_now()+timedelta(days=1)).isoformat()+'Z', 'entries':[{'text':'alma, körte!', 'repetitions':3}, {'text':'öt 12', 'repetitions':1}]})
    def snapshot(self, homework_id, status='completed', revision=0):
        return {'activity_id':f'homework_{homework_id}', 'activity_type':'homework', 'revision':revision, 'started_at':utc_now().isoformat()+'Z', 'ended_at':None if status=='in_progress' else utc_now().isoformat()+'Z', 'status':status, 'active_duration_ms':12000, 'mistake_count':2, 'keys':{'a':{'first_try_correct_count':2,'first_try_incorrect_count':1}}}
    def test_create_access_and_all_submissions(self):
        self.assertEqual(self.client.post('/api/trainer/students/2/homeworks', headers=self.trainer, json={'deadline':(utc_now()+timedelta(minutes=59)).isoformat()+'Z','entries':[{'text':'a','repetitions':1}]}).status_code,422)
        result=self.create(); self.assertEqual(result.status_code,200,result.text); hw_id=result.json()['id']
        self.assertEqual(self.client.get('/api/homeworks',headers=self.student).json()[0]['id'],hw_id)
        detail=self.client.get(f'/api/homeworks/{hw_id}',headers=self.student).json()
        self.assertEqual(len(detail['exercise']['units']),4); self.assertEqual(detail['exercise']['baselineSeconds'],30)
        self.assertEqual(self.client.get(f'/api/homeworks/{hw_id}',headers=self.other).status_code,200)
        for _ in range(2):
            url=f'/api/homeworks/{hw_id}/attempts/{uuid4()}'; snapshot=self.snapshot(hw_id)
            self.assertEqual(self.client.put(url,headers=self.student,json=snapshot).status_code,200)
            self.assertEqual(self.client.put(url,headers=self.student,json=snapshot).status_code,200)
        interrupted=self.client.put(f'/api/homeworks/{hw_id}/attempts/{uuid4()}',headers=self.student,json=self.snapshot(hw_id,'interrupted'))
        self.assertEqual(interrupted.status_code,200)
        progress=self.client.get('/api/progress',headers=self.student).json(); self.assertEqual(len(progress['attempts']),3)
        completed=[item for item in progress['attempts'] if item['status']=='completed']
        self.assertEqual(len(completed),2); self.assertTrue(all(item['score'] is not None for item in completed))
        self.assertEqual(sum(item['status']=='interrupted' for item in progress['attempts']),1)
        listing=self.client.get('/api/trainer/students/2/homeworks',headers=self.trainer).json(); self.assertEqual(len(listing[0]['attempts']),2)
        self.assertEqual(self.client.get('/api/trainer/students/2/homeworks',headers=self.other).json(),[])
        other_progress=self.client.get('/api/trainer/students/2/progress',headers=self.other).json()
        self.assertEqual(len(other_progress['attempts']),3)
        self.assertTrue(all(item['activity_id']==f'homework_{hw_id}' for item in other_progress['attempts']))
    def test_assignment_creation_retry_is_idempotent(self):
        request={'id':'a'*32,'deadline':(utc_now()+timedelta(hours=2)).isoformat()+'Z','entries':[{'text':'egy','repetitions':1}]}
        first=self.client.post('/api/trainer/students/2/homeworks',headers=self.trainer,json=request)
        second=self.client.post('/api/trainer/students/2/homeworks',headers=self.trainer,json=request)
        self.assertEqual(first.status_code,200); self.assertEqual(second.json()['id'],first.json()['id'])
        changed={**request,'entries':[{'text':'más','repetitions':1}]}
        self.assertEqual(self.client.post('/api/trainer/students/2/homeworks',headers=self.trainer,json=changed).status_code,409)
        self.assertEqual(len(self.client.get('/api/homeworks',headers=self.student).json()),1)

    def test_student_and_trainer_lists_filter_and_order_homework(self):
        ids=[self.create().json()['id'] for _ in range(4)]
        submitted_old, unsubmitted_old, expired_recent, open_id=ids
        result=self.client.put(f'/api/homeworks/{submitted_old}/attempts/{uuid4()}',headers=self.student,json=self.snapshot(submitted_old))
        self.assertEqual(result.status_code,200)
        with Session(self.engine) as session:
            session.get(Homework,submitted_old).deadline=utc_now()-timedelta(days=9)
            session.get(Homework,unsubmitted_old).deadline=utc_now()-timedelta(days=9)
            session.get(Homework,expired_recent).deadline=utc_now()-timedelta(days=6)
            session.commit()
        student=self.client.get('/api/homeworks',headers=self.student).json()
        self.assertEqual([x['id'] for x in student],[open_id,expired_recent])
        trainer=self.client.get('/api/trainer/students/2/homeworks',headers=self.trainer).json()
        self.assertEqual({x['id'] for x in trainer},{open_id,expired_recent,submitted_old})
        self.assertEqual(trainer[0]['id'],open_id)

    def test_unassigned_user_cannot_access_homework_or_submit(self):
        hw_id=self.create().json()['id']
        with Session(self.engine) as session:
            session.add(User(name='Outsider',identifier='outsider',role=Role.STUDENT,credential_hash=hasher.hash('1234')))
            session.commit()
        outsider=self.login('outsider','1234')
        self.assertEqual(self.client.get(f'/api/homeworks/{hw_id}',headers=outsider).status_code,403)
        self.assertEqual(self.client.put(f'/api/homeworks/{hw_id}/attempts/{uuid4()}',headers=outsider,json=self.snapshot(hw_id)).status_code,404)
        self.assertEqual(self.client.post('/api/trainer/students/2/homeworks',headers=outsider,json={'deadline':(utc_now()+timedelta(hours=2)).isoformat()+'Z','entries':[{'text':'a','repetitions':1}]}).status_code,403)

    def test_private_homework_audio_checks_access_before_cache_response(self):
        digest='c'*64
        pool=Path(self.directory.name)/'homework_audio'; pool.mkdir()
        (pool/f'{digest}.wav').write_bytes(b'audio')
        with patch('app.routers.homework.audio_for',return_value=f'pool:{digest}'), patch('app.routers.homework.DATABASE_PATH',Path(self.directory.name)/'db.sqlite'):
            hw_id=self.create().json()['id']
            path=f'/api/homeworks/{hw_id}/audio/{digest}'
            first=self.client.get(path,headers=self.student)
            self.assertEqual(first.status_code,200); self.assertEqual(first.content,b'audio')
            self.assertEqual(self.client.get(path,headers={**self.student,'If-None-Match':first.headers['etag']}).status_code,304)
            self.assertEqual(self.client.get(path,headers={'If-None-Match':first.headers['etag']}).status_code,401)
            self.assertEqual(self.client.get(f'/api/homeworks/{hw_id}/audio/{"d"*64}',headers=self.student).status_code,404)

    def test_reopen_preserves_previous_submissions_and_four_state_status(self):
        hw_id=self.create().json()['id']
        path=f'/api/homeworks/{hw_id}/attempts/{uuid4()}'
        self.assertEqual(self.client.put(path,headers=self.student,json=self.snapshot(hw_id)).status_code,200)
        with Session(self.engine) as session:
            session.get(Homework,hw_id).deadline=utc_now()-timedelta(minutes=1)
            session.query(HomeworkDeadline).filter_by(homework_id=hw_id).one().deadline=utc_now()-timedelta(minutes=1)
            session.commit()
        item=self.client.get('/api/homeworks',headers=self.student).json()[0]
        self.assertTrue(item['expired']); self.assertTrue(item['submitted'])
        result=self.client.post(f'/api/trainer/homeworks/{hw_id}/reopen',headers=self.trainer,json={'deadline':(utc_now()+timedelta(hours=2)).isoformat()+'Z'})
        self.assertEqual(result.status_code,200); self.assertFalse(result.json()['expired']); self.assertTrue(result.json()['submitted'])
        history=self.client.get('/api/trainer/students/2/homeworks',headers=self.trainer).json()[0]
        self.assertEqual(len(history['attempts']),1)

    def test_minimum_deadline_and_server_receipt_time(self):
        now=utc_now()
        body={'deadline':(now+timedelta(minutes=60)).isoformat()+'Z','entries':[{'text':'a','repetitions':1}]}
        with patch('app.routers.homework.utc_now',return_value=now):
            valid=self.client.post('/api/trainer/students/2/homeworks',headers=self.trainer,json=body)
            self.assertEqual(valid.status_code,200,valid.text)
            too_soon={**body,'deadline':(now+timedelta(minutes=59,seconds=59)).isoformat()+'Z'}
            self.assertEqual(self.client.post('/api/trainer/students/2/homeworks',headers=self.trainer,json=too_soon).status_code,422)
        hw_id=valid.json()['id']
        forged=self.snapshot(hw_id); forged['started_at']=(now-timedelta(days=1)).isoformat()+'Z'; forged['ended_at']=now.isoformat()+'Z'
        with patch('app.main.utc_now',return_value=now+timedelta(minutes=60)):
            self.assertEqual(self.client.put(f'/api/homeworks/{hw_id}/attempts/{uuid4()}',headers=self.student,json=forged).status_code,409)

    def test_reopen_does_not_retroactively_accept_already_late_receipt(self):
        now=utc_now()
        with patch('app.routers.homework.utc_now',return_value=now):
            created=self.client.post('/api/trainer/students/2/homeworks',headers=self.trainer,json={
                'deadline':(now+timedelta(minutes=61)).isoformat()+'Z','entries':[{'text':'a','repetitions':1}]})
        hw_id=created.json()['id']
        with patch('app.routers.homework.utc_now',return_value=now+timedelta(minutes=63)):
            reopened=self.client.post(f'/api/trainer/homeworks/{hw_id}/reopen',headers=self.trainer,json={
                'deadline':(now+timedelta(hours=3)).isoformat()+'Z'})
            self.assertEqual(reopened.status_code,200,reopened.text)
        with patch('app.main.utc_now',return_value=now+timedelta(minutes=62)):
            result=self.client.put(f'/api/homeworks/{hw_id}/attempts/{uuid4()}',headers=self.student,json=self.snapshot(hw_id))
            self.assertEqual(result.status_code,409)
        with patch('app.main.utc_now',return_value=now+timedelta(minutes=64)):
            result=self.client.put(f'/api/homeworks/{hw_id}/attempts/{uuid4()}',headers=self.student,json=self.snapshot(hw_id))
            self.assertEqual(result.status_code,200,result.text)

    def test_late_and_reopen(self):
        hw_id=self.create().json()['id']
        with Session(self.engine) as session: session.get(Homework,hw_id).deadline=utc_now()-timedelta(minutes=1); session.query(HomeworkDeadline).filter_by(homework_id=hw_id).one().deadline=utc_now()-timedelta(minutes=1); session.commit()
        url=f'/api/homeworks/{hw_id}/attempts/{uuid4()}'
        self.assertEqual(self.client.put(url,headers=self.student,json=self.snapshot(hw_id)).status_code,409)
        self.assertEqual(self.client.put(url,headers=self.student,json=self.snapshot(hw_id,'interrupted')).status_code,200)
        listing=self.client.get('/api/trainer/students/2/homeworks',headers=self.trainer).json(); self.assertTrue(listing[0]['expired']); self.assertEqual(listing[0]['attempts'],[])
        new={'deadline':(utc_now()+timedelta(hours=2)).isoformat()+'Z'}
        self.assertEqual(self.client.post(f'/api/trainer/homeworks/{hw_id}/reopen',headers=self.other,json=new).status_code,404)
        self.assertEqual(self.client.post(f'/api/trainer/homeworks/{hw_id}/reopen',headers=self.trainer,json=new).status_code,200)
        self.assertEqual(self.client.put(f'/api/homeworks/{hw_id}/attempts/{uuid4()}',headers=self.student,json=self.snapshot(hw_id)).status_code,200)
