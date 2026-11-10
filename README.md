# Gépírás

Audio-first Hungarian touch-typing tutor. Linux first; Flutter web and Windows
remain targets. Menus, lesson content, practice text, and Hungarian audio are
bundled locally. No backend, accounts, runtime TTS, or saved progress.

## Run on Linux

With Flutter and its Linux desktop dependencies installed:

```sh
flutter pub get
flutter run -d linux
```

The window starts full-screen. Playback works offline after installation.

## Menus and activities

The application starts at the spoken main menu. Up/Down selects an item;
Enter/Right opens it; Escape/Left returns to its parent. F1 repeats the selection.
Rapid navigation interrupts previous speech instead of building a speech queue.
Mouse selection is also available.

The available content is:

- **LECKÉK → A, S, D, F, J, K, L, É → betűk:** guided discovery of F. Three
  successful presses complete the activity; wrong keys are named and trigger
  coaching without resetting the success count.
- **LECKÉK → A, S, D, F, J, K, L, É → gyakorlatok:** 24 single-word targets,
  from AJ to FÉJAKÉDA, restricted to the eight lesson letters. Geometric patterns
  are prompted with the approved letter recordings; words and word-like targets
  use word recordings.
- **LECKÉK → I, R → betűk:** F→R and K→I reaching practice. The anchor keys
  require one successful press each; R and I each require three total successes.
  Incorrect keys do not reset the count. Movement and retry instructions identify
  both the anchor key and the finger.
- **LECKÉK → I, R → gyakorlatok — I / R / IR:** three meaningful-word sessions,
  containing 28, 31, and 21 targets respectively, in the supplied order. The I
  session allows ASDFJKLÉI; R allows ASDFJKLÉR; IR allows ASDFJKLÉIR.
- **GYAKORLÁS → könnyű → Mintagyakorlás – öt mondat:** the original five sample
  sentences, with sentence narration, three-two-one, and individual word prompts.

Enter starts an opened activity. Escape pauses it and opens a spoken menu with
Continue, Restart, and Return to Menu. Escape from that menu resumes. Completion
opens a menu offering Restart and Return to Menu. Parent-menu selection is
preserved when returning from an activity. Ctrl+W, F4, or Close exits.

## Typing behavior

- Case and spaces are ignored; Hungarian accents must match. Source text keeps
  punctuation, while current typing targets contain letters only. Strict typing
  of spaces and punctuation is deferred.
- Correct characters play a short good tone. Wrong characters play a buzz.
- F3 toggles Simple/Advanced and announces the mode. Simple is the launch default;
  the selection survives activity changes and exercise restarts.
- Simple ignores wrong characters; Backspace does nothing.
- Advanced retains mistakes and subsequent characters. Backspace removes the
  last entered character, including correct characters, within the current word.
  The incorrect suffix is shown in red and must be deleted before continuing.
- Switching to Simple discards that suffix and preserves the correct prefix.
- Words advance on their last correct character. Completed words stay completed.
  The word reward is `correct.mp3`; sentence completion also plays `fanfare.mp3`.
- F1 repeats the word. F2 spells actual entered characters, including mistakes,
  with 250 ms between recordings. Any key-down cancels F2 before its normal
  action; releases have no effect. Symbols outside the alphabet use a spoken
  “Ismeretlen jel” fallback.
- Typing stays active during word prompts and rewards. Input during sentence
  narration/countdown is ignored. Changing mode during these instructions
  restarts them after the announcement.
- Leaving the application pauses the activity. Resuming interrupted sentence
  instructions restarts narration/countdown; accepted input is preserved.

Letter teaching uses its own coaching flow independently of typing correction
modes. F1 repeats its current instruction; F3 changes the selection for subsequent
word/practice activities.

## Content

`data/menu.json` contains the main menu tree and pause/completion menus. Branches
have `children`; activity leaves have a `type` and a content asset reference.
The supported activity identifiers are `letters`, `words`, and `practice`.
They select application execution flows; JSON contains no executable callbacks.
Stable IDs determine audio filenames. Titles and optional `speech` text determine
what appears on screen and is spoken. Only available content is listed.

- `data/lessons/home_row_letters.json`: ordered teaching steps with a target key,
  required success count, instruction, retry, success, and completion phrases.
  Anchor/movement sequences can be expressed as multiple steps.
- `data/lessons/home_row_words.json`: allowed letters and ordered targets.
  A target's `promptStyle` is `word` or `letters`.
- `data/lessons/upper_row_ir_letters.json`: F→R and K→I teaching steps.
- `data/lessons/upper_row_i_words.json`, `upper_row_r_words.json`, and
  `upper_row_ir_words.json`: the three lesson-2 word lists and their permitted
  letters.
- `data/practice/sample.json`: original text divided into sentence units.

Typed models validate menu shape, IDs, nonempty activities, activity types, and
permitted letters. Adding content of an existing type requires editing JSON,
regenerating its speech, and rebuilding the app. No source-code menu edits are
needed. New content directories must also be declared in `pubspec.yaml`.

## Structure

- `lib/main.dart`: initialization and dependency wiring.
- `lib/app.dart`: application lifecycle bridge, theme, and top-level navigation.
- `lib/controllers`: application flow and audio orchestration; controllers notify
  the presentation layer and delegate mechanics to managers.
- `lib/managers`: pure Dart typing and guided-teaching rules, state transitions,
  correction, and progression. No Flutter or audio imports.
- `lib/models`: immutable content and state snapshots.
- `lib/screens`: stateless screens receiving data and callbacks.
- `lib/widgets`: reusable display, keyboard mapping, and menu scrolling. The menu
  list owns only its scroll position; navigation decisions stay in the controller.
- `lib/services`: bundled-content access, audio playback, and interruptible speech.
- `lib/utils`: pure text normalization.

The application owns audio initialization/disposal. Leaving an activity cancels
its speech and pending progression while keeping audio available to menus and
other activities. Shared cues and menu recordings load at startup; activity
recordings load on entry and remain cached.

## Audio assets

Speech uses Hungarian gTTS with normal speed. Generation requires internet;
playback does not. The approved alphabet uses `aa` for a, `emm` for m, and `err`
for r; other vowels are single letters. The original good tone is 28 ms. The
60 ms error buzz combines 600, 1800, and 3000 Hz, with short fades.

```sh
python3 -m venv .venv
.venv/bin/pip install -r tool/requirements.txt
.venv/bin/python tool/generate_audio.py
```

The generator reads the menu's referenced JSON content. Existing recordings are
reused when spoken text is unchanged; `--force` regenerates speech. The manifest
records text, provider, and speech checksums. Approved alphabet clips are reused.

SoLoud uses a 256-frame buffer at 48 kHz (5.3 ms mixing quantum), which does not
measure total device latency. The bundled font license is in
`assets/fonts/LICENSE.txt`.

## Checks

```sh
flutter analyze
flutter test
flutter build linux
flutter test integration_test/linux_prototype_test.dart -d linux
flutter test integration_test/lesson_two_test.dart -d linux
```

The native check needs a desktop/audio device and exercises spoken menus, F
teaching, all 24 word drills, correction, and the five-sentence practice flow.
The lesson-2 native check exercises the four teaching steps and all 80 words.
The game managers are pure Dart and can be tested independently of screens.
