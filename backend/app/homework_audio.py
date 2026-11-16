"""Reuse Hungarian gTTS clips from the shipped manifest or a local pool."""
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

from gtts import gTTS

from .config import DATABASE_PATH, ROOT

WORD_PATTERN = re.compile(r'[^\W_]+', re.UNICODE)
PROVIDER = 'gTTS / Google Translate, hu, default voice, normal speed'


def targets(text: str) -> list[str]:
    return WORD_PATTERN.findall(text)


def resolve_asset(homework_id: str, value: str) -> str:
    if not value.startswith('pool:'):
        return value
    return f'assets/audio/homework_audio_{homework_id}_{value[5:]}.wav'


def audio_for(text: str) -> str:
    digest = hashlib.sha256(json.dumps([text, 'hu', False], ensure_ascii=False).encode()).hexdigest()
    manifest = ROOT / 'assets' / 'audio' / 'manifest.json'
    for name, details in json.loads(manifest.read_text(encoding='utf-8')).items():
        path = ROOT / 'assets' / 'audio' / f'{name}.wav'
        if details.get('text') == text and details.get('provider') == PROVIDER and path.is_file():
            return f'assets/audio/{name}.wav'
    pool = DATABASE_PATH.parent / 'homework_audio'
    output = pool / f'{digest}.wav'
    if not output.is_file():
        pool.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=pool) as directory:
            mp3 = Path(directory) / 'speech.mp3'
            wav = Path(directory) / 'speech.wav'
            gTTS(text=text, lang='hu', slow=False, timeout=(10, 45)).save(str(mp3))
            subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(mp3),
                            '-af', 'silenceremove=start_periods=1:start_duration=0.005:start_threshold=-48dB',
                            '-ar', '48000', '-ac', '1', '-c:a', 'pcm_s16le', str(wav)], check=True)
            os.replace(wav, output)
    return f'pool:{digest}'
