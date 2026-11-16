import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from app.homework_audio import audio_for

class HomeworkAudioTests(unittest.TestCase):
    def test_reuses_existing_and_generated_clips(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); audio=root/'assets'/'audio'; audio.mkdir(parents=True)
            (audio/'existing.wav').write_bytes(b'wave')
            (audio/'manifest.json').write_text(json.dumps({'existing':{'text':'alma','provider':'gTTS / Google Translate, hu, default voice, normal speed'}}))
            class FakeSpeech:
                calls=0
                def __init__(self, **kwargs): FakeSpeech.calls+=1
                def save(self, path): Path(path).write_bytes(b'mp3')
            def fake_ffmpeg(command, check): Path(command[-1]).write_bytes(b'wav')
            with patch('app.homework_audio.ROOT',root), patch('app.homework_audio.DATABASE_PATH',root/'instance'/'usage.db'), patch('app.homework_audio.gTTS',FakeSpeech), patch('app.homework_audio.subprocess.run',fake_ffmpeg):
                self.assertEqual(audio_for('alma'),'assets/audio/existing.wav')
                first=audio_for('Új szöveg!'); second=audio_for('Új szöveg!')
                self.assertTrue(first.startswith('pool:')); self.assertEqual(first,second); self.assertEqual(FakeSpeech.calls,1)
