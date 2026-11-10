# Gépírás

Frontend-only Hungarian audio typing prototype. Linux first; Flutter web and
Windows remain targets. No accounts, backend, session storage, or runtime TTS.

## Run on Linux

With Flutter and its Linux desktop build dependencies installed:

```sh
flutter pub get
flutter run -d linux
```

The Linux window starts full-screen. Audio and a Hungarian-capable monospace
font are bundled; running the app needs no internet connection.

## Interaction

- Enter starts; after all five sentences, Enter restarts.
- Hear the full sentence, then three, two, one, then individual words.
- Type letters in either case. Spaces are ignored. Accents must match.
- Correct characters play a short good tone and advance. Wrong characters play
  a short buzz.
- F3 toggles Simple/Advanced and announces the mode in Hungarian. Simple is the
  default on launch; the selected mode survives exercise restarts.
- Simple ignores wrong characters; Backspace has no effect.
- Advanced retains mistakes and all subsequent characters. Backspace deletes
  the last entered character, including correct characters, within the current
  word. Clear the incorrect suffix before continuing. Mistakes appear in red.
- Switching to Simple discards the incorrect suffix and preserves the correct
  prefix. Changing mode during sentence reading/countdown restarts those
  instructions after the mode announcement.
- Words advance on the last correct character, without requiring a space.
- Each completed word plays `correct.mp3`; sentence completion follows it with
  `fanfare.mp3`. Celebrations finish before the next spoken prompt. Typing stays
  active between words, and advancing again or repeating interrupts the reward.
- Type during word speech. Completing the word interrupts its speech and starts
  the next word. Input during the sentence reading/countdown is ignored.
- F1 repeats the current word without resetting progress.
- F2 spells the entered characters of the current word, including mistakes in
  Advanced mode, with 250 ms between
  recordings. An empty prefix is silent. Any key-down (including modifiers and
  held-key repeats) interrupts spelling before its normal action; key releases
  have no effect. F2 restarts spelling without changing progress.
  Symbols outside the bundled alphabet are spoken as “Ismeretlen jel”.
- Escape pauses/resumes. Leaving the app pauses an active exercise as well.
  Resuming a word repeats it; resuming interrupted instructions restarts the
  sentence reading/countdown.
- Close, Ctrl+W, or F4 exits on Linux.

## Structure

- `lib/models`: immutable sentence content and audio references.
- `lib/controllers`: progression and validation; its only Flutter import is
  `foundation`. Depends on a plain Dart audio interface.
- `lib/services`: audio interface and SoLoud implementation. Sounds are decoded
  into memory before starting. Beeps trigger synchronously and are not queued
  behind speech or previous keystrokes.
- `lib/widgets`: stateless display and keyboard event capture, receiving data
  and callbacks. The current word has fixed letter slots to prevent shifting.
- `lib/main.dart`: ownership, lifecycle, theme, and listenable builder wiring.

The current mode is displayed near the bottom of the screen.

## Audio assets

Bundled speech was generated separately for each sentence, word, and spoken cue
using gTTS in Hungarian with its default voice and normal speed. Generation
requires internet; playback does not. gTTS has no explicit gender/quality setting.
The original good tone is a 28 ms mono PCM WAV. The error buzz lasts 60 ms and
combines 600, 1800, and 3000 Hz components. Both use short fades.
The supplied word/sentence celebration sounds are preloaded MP3 assets.

To regenerate (Python, ffmpeg, and the listed Python dependency are needed):

```sh
python3 -m venv .venv
.venv/bin/pip install -r tool/requirements.txt
.venv/bin/python tool/generate_audio.py
```

The script reads sentence content from the model. Existing recordings are reused
when their text is unchanged; `--force` regenerates all speech. The audio manifest
records the spoken text, provider, and speech checksums.
Letter recordings use the reviewed Hungarian names: `aa` for a, `emm` for m,
`err` for r, and single vowels for the other vowels.
The bundled welcome explains F2, F3, and correction with Backspace in Advanced
mode. Mode announcements are bundled as well.

SoLoud uses a 256-frame buffer at 48 kHz (5.3 ms mixing quantum). This is not a
guarantee of end-to-end latency; measure responsiveness on the intended audio
device. The bundled DejaVu Sans Mono font license is in `assets/fonts/LICENSE.txt`.

## Checks

```sh
flutter analyze
flutter test
flutter build linux
```

With a Linux desktop and an audio output device available, the native integration
check exercises the real audio engine and all five sentences:

```sh
flutter test integration_test/linux_prototype_test.dart -d linux
```

The web audio initialization script is included for the later web build.
Browsers require a user gesture to enable audio, and ordinary browser tabs cannot
reliably be closed programmatically; web startup/exit behavior needs adapting
when web becomes the active target.
