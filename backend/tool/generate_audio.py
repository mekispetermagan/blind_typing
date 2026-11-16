#!/usr/bin/env python3
"""Generate bundled Hungarian gTTS speech and original feedback sounds.

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


ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "assets" / "audio"
RATE = 48000

# Reusable progress-view speech fragments. Status clips are bundled separately.
PROGRESS_SPEECH = {
    'progress_return_main': 'Vissza a főmenübe. Az Enter visszalép.',
    'progress_help': 'A fel és le nyíllal lépkedhetsz az elemek között. A bal és jobb nyíl szakaszt vált. A Home és End a szakasz első és utolsó elemére ugrik. Az F egy ismétel. Az Escape visszalép.',
    'progress_section_week': 'Az elmúlt 7 napban',
    'progress_section_activity': 'Heti gyakorlás',
    'progress_section_letters': 'Betűstatisztika',
    'progress_section_recent': 'Legutóbbi feladatok',
    'progress_completed': 'Befejezett feladatok',
    'progress_interrupted': 'Megszakított feladatok',
    'progress_duration': 'Aktív gyakorlási idő',
    'progress_correct': 'Elsőre helyes',
    'progress_incorrect': 'Elsőre hibás',
    'progress_total': 'Összesen',
    'progress_percent': 'százalék helyes',
    'progress_week': 'Hét',
    'progress_until': 'eddig',
    'progress_date': 'Dátum',
    'progress_activity': 'Feladat',
    'progress_finished': 'Befejezve',
    'progress_stopped': 'Megszakítva',
    'progress_empty_letters': 'Még nincs betűstatisztika.',
    'progress_empty_recent': 'Még nincsenek feladatok.',
}
for _index, _name in enumerate(['január', 'február', 'március', 'április', 'május', 'június', 'július', 'augusztus', 'szeptember', 'október', 'november', 'december'], 1):
    PROGRESS_SPEECH[f'progress_month_{_index}'] = _name
for _index, _name in enumerate(['hétfő', 'kedd', 'szerda', 'csütörtök', 'péntek', 'szombat', 'vasárnap'], 1):
    PROGRESS_SPEECH[f'progress_day_{_index}'] = _name


def typing_words(text):
    if re.fullmatch(r"[0-9]+", text):
        return [text]
    return re.findall(r"[A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]+", text)


def speech_texts():
    catalog = json.loads((ROOT / "data" / "menu.json").read_text())
    references = {}
    def walk(node):
        if node.get('command') != 'previous':
            yield f"menu_{node['id']}", node.get("speech", node["title"])
        if "activity" in node:
            reference = node["activity"]
            references[reference["content"]] = reference["type"]
        for child in node.get("children", []):
            yield from walk(child)
    yield 'menu_previous', 'Vissza az előző menübe'
    yield 'homework_row', 'Sor'
    yield 'homework_trainer_list_help', 'A fel és le nyíllal válassz házi feladatot. Az Enter megnyitja a beadásokat. Az R újranyitja a lejárt feladatot. Az F egy ismétel. Az Escape visszalép.'
    yield 'homework_comma', 'vessző'
    yield 'homework_colon', 'kettőspont'
    yield 'homework_dash', 'kötőjel'
    yield 'homework_question', 'kérdőjel'
    yield 'homework_exclamation', 'felkiáltójel'
    yield 'homework_semicolon', 'pontosvessző'
    yield 'homework_slash', 'perjel'
    yield 'homework_open_paren', 'nyitó zárójel'
    yield 'homework_close_paren', 'záró zárójel'
    yield 'homework_quote', 'idézőjel'
    yield 'homework_apostrophe', 'aposztróf'

    yield 'menu_homeworks', 'Házi feladatok'
    yield 'menu_add_homework', 'Házi feladat feladása'
    yield 'menu_view_homeworks', 'Házi feladatok megtekintése'
    yield 'student_selection_homework_help', 'Válassz tanulót a fel és le nyíllal. Az Enter kiválasztja. Az F egy ismétel. Az Escape visszalép.'
    yield 'homework_form_help', 'Házi feladat. Tab vált a mezők között. A dátum év-hónap-nap formátumú, az idő óra-perc. Az Enter új sort ad hozzá. A feladat elküldéséhez válaszd a feladás gombot. Az F egy megismétli az aktuális mezőt.'
    yield 'homework_date', 'Határidő dátuma, év-hónap-nap'
    yield 'homework_time', 'Határidő ideje, óra-perc'
    yield 'homework_entry', 'Gyakorlandó szöveg'
    yield 'homework_repetitions', 'Ismétlések száma'
    yield 'homework_add_row', 'Új sor hozzáadása'
    yield 'homework_remove_row', 'Sor törlése'
    yield 'homework_reopen', 'Újranyitás új határidővel'
    yield 'homework_save_deadline', 'Új határidő mentése'
    yield 'homework_invalid', 'Hibás adat. A határidő legalább hatvan perccel legyen később, és minden sor tartalmazzon szöveget és pozitív ismétlésszámot.'
    yield 'homework_saving', 'Házi feladat mentése és hangok készítése. Kérlek várj.'
    yield 'homework_created', 'A házi feladat mentve.'
    yield 'homework_list_help', 'A fel és le nyíllal választhatsz. Az Enter megnyitja. Az F egy ismétel. Az Escape visszalép.'
    yield 'homework_empty', 'Nincs megjeleníthető házi feladat.'
    yield 'homework_deadline', 'Határidő'
    yield 'homework_status_open_unsubmitted', 'Nyitott, nincs beadva'
    yield 'homework_status_open_submitted', 'Nyitott, beadva'
    yield 'homework_status_expired_unsubmitted', 'Lejárt, nincs beadva'
    yield 'homework_status_expired_submitted', 'Lejárt, beadva'
    yield 'homework_no_attempt', 'Még nincs beadás'
    yield 'homework_latest', 'Legutóbbi beadás'
    yield 'homework_earlier', 'Korábbi beadások megtekintése'
    yield 'homework_attempts_help', 'Korábbi beadások. A fel és le nyíllal választhatsz. Az F egy ismétel. Az Escape visszalép.'
    yield 'homework_start_expired', 'A határidő lejárt. A feladat nem adható be.'
    yield 'homework_completion_pending', 'A beadás folyamatban van.'
    yield 'homework_completion_saved', 'A házi feladat beadva.'
    yield 'homework_completion_expired', 'A beadás nem sikerült, mert a határidő lejárt. A gyakorlás megszakítottként szerepel.'
    yield 'homework_back_list', 'Vissza a házi feladatokhoz'
    yield 'homework_try_again', 'Újrapróbálás'
    yield 'homework_back_main', 'Vissza a főmenübe'
    yield 'homework_delete', 'Törlés'
    yield 'homework_space', 'szóköz'
    yield 'homework_punctuation', 'Írásjel'

    yield 'menu_student_progress', 'Tanulók haladása'
    yield 'student_selection_help', 'Válassz tanulót a fel és le nyíllal. Az Enter megnyitja a haladási adatokat. Az F egy ismétel. Az Escape visszalép.'
    yield 'student_selection_empty', 'Nincsenek hozzád rendelt tanulók.'
    yield 'student_selection_return', 'Vissza az oktatói főmenübe'
    yield 'progress_return_students', 'Vissza a tanulókhoz. Az Enter visszalép.'
    yield 'menu_area_welcome', 'A fel és le nyíllal választhatsz. Az Enter megnyitja a kijelölt elemet. Az F egy megismétli a kijelölt elemet.'
    yield 'menu_area_selection', 'Válassz területet! A fel és le nyíllal választhatsz. Az Enter megnyitja a kijelölt területet. Az F egy megismétli a kijelölt elemet.'
    yield 'menu_area_admin', 'Adminisztrátor'
    yield 'menu_area_trainer', 'Oktató'
    yield 'menu_area_student', 'Tanuló'
    yield 'menu_area_selector', 'Vissza a területválasztóhoz'
    yield 'menu_admin_main', 'Adminisztrátor főmenü'
    yield 'menu_trainer_main', 'Oktatói főmenü'
    for menu in (catalog["root"], catalog["pause"], catalog["complete"]):
        yield from walk(menu)
    for asset, activity_type in references.items():
        content = json.loads((ROOT / asset).read_text())
        if content["type"] != activity_type:
            raise ValueError(f"Activity type mismatch: {asset}")
        if activity_type == "letters":
            for step in content["steps"]:
                for cue in ["instruction", "retry", "success", "complete"]:
                    yield f"step_{step['id']}_{cue}", step[cue]
        else:
            for unit in content["units"]:
                if activity_type == "practice":
                    yield f"{unit['id']}_sentence", unit["text"]
                words = typing_words(unit["text"])
                if unit.get("promptStyle", "word") == "word":
                    for index, word in enumerate(words):
                        speech = unit.get("speech", word.lower()) if activity_type == "words" else word
                        yield f"{unit['id']}_word_{index}", speech
    yield "count_3", "három"
    yield "count_2", "kettő"
    yield "count_1", "egy"
    letters = "aábcdeéfghiíjklmnoóöőpqrstuúüűvwxyz"
    names = [
        "aa", "á", "bé", "cé", "dé", "e", "é", "ef", "gé", "há", "i", "hosszú í",
        "jé", "ká", "el", "emm", "en", "o", "hosszú ó", "ö", "hosszú ő", "pé", "kú", "err",
        "es", "té", "u", "hosszú ú", "ü", "hosszú ű", "vé", "duplavé", "iksz", "ipszilon", "zé",
    ]
    for letter, name in zip(letters, names, strict=True):
        yield f"letter_{ord(letter):04x}", name
    yield "welcome", (
        "A kezdéshez nyomd meg az Enter billentyűt. "
        "Gépeld a hallott szót. A szóköz nem szükséges. "
        "Az F egy megismétli a szót. "
        "Az F kettő felolvassa a már beírt betűket. "
        "Ezt bármelyik billentyű megnyomása megszakítja. "
        "Az F három vált az egyszerű és a haladó mód között. "
        "Haladó módban a hibás betűket a Backspace billentyűvel törölheted. "
        "Az Escape szüneteltet. "
        "Az F négy kilép. A szünet menüben visszatérhetsz a feladatválasztáshoz."
    )
    yield "paused", "Szünet. A folytatáshoz nyomd meg az Escape billentyűt."
    yield "complete", (
        "Ügyes vagy! Kész a feladat. Az Enter újrakezdi. "
        "A többi lehetőséghez használd a lefelé nyilat. "
        "A kiválasztott lehetőséget az Enterrel nyithatod meg."
    )
    yield "menu_welcome", (
        "Üdvözöllek! A fel és le nyíllal választhatsz. Az Enter megnyitja a kijelölt elemet. "
        "Az Escape visszalép. Az F egy megismétli a kijelölt elemet. "
        "Az F három módot vált. Az F négy kilép."
    )
    yield "teaching_welcome", (
        "Az Enter indítja a betűk tanulását. Kövesd a hallott útmutatót. "
        "Az F egy megismétli az útmutatót. Az Escape megnyitja a szünet menüt."
    )
    yield "wrong_key_prefix", "Ez egy"
    yield "wrong_key_suffix", "volt."
    yield "content_error", "A feladat nem tölthető be. Az Enter újrapróbálja. Az Escape visszalép."
    yield "mode_simple", "Egyszerű mód."
    yield "mode_advanced", "Haladó mód."
    yield "unknown_character", "Ismeretlen jel."

    yield from PROGRESS_SPEECH.items()

    yield "result_time", "Az időd"
    yield "result_minute", "perc"
    yield "result_second", "másodperc."
    yield "result_errors", "A hibás leütések száma"
    yield "result_score", "A pontszámod"
    yield "result_high_score", "Az eddigi legmagasabb pontszámod"
    yield "result_best_time", "Ez eddig a legjobb időd."
    yield "result_fewest_errors", "Ez eddig a legkevesebb hibád."
    yield "result_mixed_mode", "A feladat közben módot váltottál."
    for name, text in [
        ("hundred", "száz"),
        ("thousand", "ezer"),
        ("million", "millió"),
        ("billion", "milliárd"),
    ]:
        yield f"result_{name}", text
    digits = ["nulla", "egy", "kettő", "három", "négy", "öt", "hat", "hét", "nyolc", "kilenc"]
    tens = ["", "tíz", "húsz", "harminc", "negyven", "ötven", "hatvan", "hetven", "nyolcvan", "kilencven"]
    for number in range(100):
        decade, digit = divmod(number, 10)
        stem = {1: "tizen", 2: "huszon"}.get(decade, tens[decade]) if digit else tens[decade]
        if number not in (1, 2, 3):
            text = digits[number] if not decade else stem + (digits[digit] if digit else "")
            yield f"result_number_{number}", text
        if digit == 2:
            yield f"result_number_{number}_before_unit", stem + "két"


def generate_beep(name, correct):
    duration = 0.028 if correct else 0.060
    frames = round(RATE * duration)
    samples = array.array("h")
    for frame in range(frames):
        t = frame / RATE
        # Short attack/release avoids clicks. The error buzz uses stronger
        # midrange harmonics so it remains distinct on small speakers.
        envelope = min(1, t / 0.002, (duration - t) / 0.005)
        if correct:
            signal = math.sin(2 * math.pi * 1050 * t)
        else:
            signal = (math.sin(2 * math.pi * 600 * t)
                      + 0.5 * math.sin(2 * math.pi * 1800 * t)
                      + 0.25 * math.sin(2 * math.pi * 3000 * t)) / 1.75
        amplitude = 0.32 if correct else 0.45
        samples.append(round(32767 * amplitude * envelope * signal))
    import sys
    if sys.byteorder != "little":
        samples.byteswap()
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(samples.tobytes())


def main():
    from gtts import gTTS

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
        entries[name] = {
            "source": "Original synthesized tone" if correct else "Original synthesized buzz",
            "duration_ms": 28 if correct else 60,
        }
    manifest_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print(f"Ready: {len(entries)} audio assets in {AUDIO}")


if __name__ == "__main__":
    main()
