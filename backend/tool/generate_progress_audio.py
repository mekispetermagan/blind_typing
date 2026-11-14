#!/usr/bin/env python3
"""Generate progress speech and the frontend's offline loading/error clips."""
import hashlib
import json
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from gtts import gTTS
from generate_audio import PROGRESS_SPEECH, ROOT, RATE

BUNDLED = {
    'progress_loading': 'A haladási adatok betöltése. Kérlek várj.',
    'progress_failure': 'A haladási adatok nem tölthetők be. Az Enter újrapróbálja. Az Escape visszalép.',
}


def generate(name, text, directory):
    output = directory / f'{name}.wav'
    with tempfile.TemporaryDirectory() as temporary:
        mp3 = Path(temporary) / 'speech.mp3'
        gTTS(text=text, lang='hu', slow=False, timeout=(10, 45)).save(str(mp3))
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(mp3),
            '-af', 'silenceremove=start_periods=1:start_duration=0.005:start_threshold=-48dB',
            '-ar', str(RATE), '-ac', '1', '-c:a', 'pcm_s16le', str(output),
        ], check=True)
    return name, text, output


def main():
    audio = ROOT / 'assets' / 'audio'
    bundled = ROOT.parent / 'frontend' / 'assets' / 'audio'
    manifest_path = audio / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    jobs = [(name, text, audio) for name, text in PROGRESS_SPEECH.items()]
    jobs += [(name, text, bundled) for name, text in BUNDLED.items()]
    with ThreadPoolExecutor(max_workers=4) as executor:
        for name, text, output in executor.map(lambda args: generate(*args), jobs):
            if name not in BUNDLED:
                manifest[name] = {'text': text, 'provider': 'gTTS / Google Translate, hu, default voice, normal speed',
                                  'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
            print(f'Generated {output}', flush=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
