#!/usr/bin/env python3
"""Generate bundled Hungarian gTTS speech and original 28 ms feedback sounds.

Requires Python, gTTS, and ffmpeg. Network access is used only by this tool.
Sentence and word recordings are requested independently, never sliced.
"""

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile
import wave

from gtts import gTTS

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "assets" / "audio"
RATE = 48000


def speech_texts():
    model = (ROOT / "lib" / "models" / "sentence.dart").read_text()
    sentences = re.findall(r"Sentence\(id: '([^']+)', text: '([^']+)'\)", model)
    if len(sentences) != 5:
        raise ValueError("Expected five sample sentences in the sentence model")
    for sentence_id, text in sentences:
        yield f"{sentence_id}_sentence", text
        for index, word in enumerate(text.split()):
            yield f"{sentence_id}_word_{index}", word
    yield "count_3", "három"
    yield "count_2", "kettő"
    yield "count_1", "egy"
    letters = "aábcdeéfghiíjklmnoóöőpqrstuúüűvwxyz"
    names = [
        "aa", "á", "bé", "cé", "dé", "e", "é", "ef", "gé", "há", "i", "í",
        "jé", "ká", "el", "emm", "en", "o", "ó", "ö", "ő", "pé", "kú", "err",
        "es", "té", "u", "ú", "ü", "ű", "vé", "duplavé", "iksz", "ipszilon", "zé",
    ]
    for letter, name in zip(letters, names, strict=True):
        yield f"letter_{ord(letter):04x}", name
    yield "welcome", (
        "A kezdéshez nyomd meg az Enter billentyűt. "
        "Gépeld a hallott szót. A szóköz nem szükséges. "
        "Az F egy megismétli a szót. "
        "Az F kettő felolvassa a már beírt betűket. "
        "Ezt bármelyik billentyű megnyomása megszakítja. "
        "Az Escape szüneteltet. "
        "Az F négy kilép."
    )
    yield "paused", "Szünet. A folytatáshoz nyomd meg az Escape billentyűt."
    yield "complete", "Ügyes vagy! Kész az öt mondat. Az Enter újrakezdi a gyakorlást."


def generate_beep(name, correct):
    duration = 0.028
    frames = round(RATE * duration)
    samples = array.array("h")
    for frame in range(frames):
        t = frame / RATE
        # Short attack/release avoids clicks. Bad feedback has a lower,
        # rougher timbre as well as a different pitch.
        envelope = min(1, t / 0.002, (duration - t) / 0.005)
        if correct:
            signal = math.sin(2 * math.pi * 1050 * t)
        else:
            signal = (math.sin(2 * math.pi * 220 * t)
                      + 0.4 * math.sin(2 * math.pi * 330 * t)) / 1.4
        samples.append(round(32767 * 0.32 * envelope * signal))
    import sys
    if sys.byteorder != "little":
        samples.byteswap()
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(samples.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="Regenerate existing speech")
    args = parser.parse_args()
    AUDIO.mkdir(parents=True, exist_ok=True)
    manifest_path = AUDIO / "manifest.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    entries = {}
    for name, text in speech_texts():
        output = AUDIO / f"{name}.wav"
        if args.force or not output.exists() or previous.get(name, {}).get("text") != text:
            print(f"Generating {name}: {text}", flush=True)
            with tempfile.TemporaryDirectory() as temporary:
                mp3 = Path(temporary) / "speech.mp3"
                gTTS(text=text, lang="hu", slow=False, timeout=(10, 45)).save(str(mp3))
                subprocess.run([
                    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(mp3), "-af",
                    "silenceremove=start_periods=1:start_duration=0.005:start_threshold=-48dB",
                    "-ar", str(RATE), "-ac", "1", "-c:a", "pcm_s16le", str(output),
                ], check=True)
        entries[name] = {
            "text": text,
            "provider": "gTTS / Google Translate, hu, default voice, normal speed",
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        }
        # Write incrementally, allowing interrupted runs to resume.
        manifest_path.write_text(json.dumps({**previous, **entries}, ensure_ascii=False, indent=2) + "\n")
    for name, correct in [("good", True), ("bad", False)]:
        generate_beep(name, correct)
        entries[name] = {"source": "Original synthesized tone", "duration_ms": 28}
    manifest_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print(f"Ready: {len(entries)} audio assets in {AUDIO}")


if __name__ == "__main__":
    main()
