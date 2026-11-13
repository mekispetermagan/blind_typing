import 'dart:io';
import 'dart:convert';

import 'package:blind_typing/managers/letter_teaching_manager.dart';
import 'package:blind_typing/managers/typing_session_manager.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/menu.dart';
import 'package:blind_typing/models/teaching_state.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/models/typing_unit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/content_fixtures.dart';

void main() {
  test('F teaching requires three total successes, retaining them through errors and pauses', () {
    final lesson = LetterTeachingManager(letterExercise)
      ..ready()
      ..restart();
    expect(lesson.typeCharacter('g'), TeachingResult.incorrect);
    expect(lesson.typeCharacter('F'), TeachingResult.accepted);
    expect(lesson.typeCharacter('g'), TeachingResult.incorrect);
    expect(lesson.state.successes, 1);
    lesson.pause();
    expect(lesson.typeCharacter('f'), TeachingResult.ignored);
    lesson.resume();
    expect(lesson.typeCharacter('f'), TeachingResult.accepted);
    expect(lesson.typeCharacter('f'), TeachingResult.completed);
    expect(lesson.state.successes, 3);
    expect(lesson.typeCharacter('f'), TeachingResult.ignored);
    lesson.restart();
    expect(lesson.state.successes, 0);
  });

  test(
    'teaching supports an anchor and a reaching step without a new engine',
    () {
      final f = letterExercise.steps.first;
      final r = LetterStep(
        id: 'reach_r',
        key: 'R',
        instruction: 'R',
        retry: 'R',
        success: 'R',
        complete: 'R',
        requiredSuccesses: 1,
      );
      final manager =
          LetterTeachingManager(
              LetterExercise(id: 'reach', title: 'Reach', steps: [f, r]),
            )
            ..ready()
            ..restart();
      manager.typeCharacter('f');
      manager.typeCharacter('f');
      expect(manager.typeCharacter('f'), TeachingResult.stepAdvanced);
      expect(manager.step.key, 'R');
      expect(manager.typeCharacter('f'), TeachingResult.ignored);
      manager.beginStep();
      expect(manager.typeCharacter('r'), TeachingResult.completed);
    },
  );

  test(
    '24 word drills advance directly without story reading or countdown',
    () {
      final manager = TypingSessionManager(wordExercise)
        ..ready()
        ..restart();
      expect(manager.state.phase, ExercisePhase.typing);
      for (var index = 0; index < wordExercise.units.length; index++) {
        expect(manager.state.sentenceIndex, index);
        for (final character
            in wordExercise.units[index].text.toLowerCase().split('')) {
          manager.typeCharacter(character);
        }
        expect(
          manager.state.phase,
          index == 23 ? ExercisePhase.complete : ExercisePhase.typing,
        );
      }
    },
  );

  test(
    'Advanced deletion and switching mode preserve the valid prefix without UI',
    () {
      final manager =
          TypingSessionManager(wordExercise, mode: TypingMode.advanced)
            ..ready()
            ..restart();
      for (final character in ['A', 'x', 'J']) {
        manager.typeCharacter(character);
      }
      expect(manager.state.enteredCharacters, ['A', 'x', 'J']);
      expect(manager.state.letterIndex, 1);
      manager.backspace();
      manager.toggleMode();
      expect(manager.state.enteredCharacters, ['A']);
      manager.toggleMode();
      manager.backspace();
      expect(manager.state.letterIndex, 0);
      manager.typeCharacter('a');
      expect(manager.typeCharacter('j'), TypingResult.unitAdvanced);
      expect(manager.state.enteredCharacters, isEmpty);
    },
  );

  test('source punctuation is preserved while current targets contain letters only', () {
    final unit = TypingUnit(id: 'punctuation', text: '„Anna”, almát! 123');
    expect(unit.text, '„Anna”, almát! 123');
    expect(unit.words, ['Anna', 'almát']);
  });

  test('content references, audio, exercise count, and allowed letters are consistent', () {
    final catalog = MenuCatalog.fromJson(readData('data/menu.json'));
    final types = <ActivityType>{};
    for (final node in catalog.allNodes) {
      expect(
        File('../backend/${node.audioAsset}').existsSync(),
        isTrue,
        reason: node.audioAsset,
      );
      final reference = node.activity;
      if (reference == null) continue;
      final exercise = ExerciseDefinition.fromJson(readData(reference.content));
      expect(exercise.type, reference.type);
      types.add(exercise.type);
      for (final audio in exercise.audioAssets) {
        expect(File('../backend/$audio').existsSync(), isTrue, reason: audio);
      }
    }
    expect(types, {ActivityType.letters, ActivityType.words});
    expect(wordExercise.units, hasLength(24));
    expect(wordExercise.units.first.text, 'AJ');
    expect(wordExercise.units.last.text, 'FÉJAKÉDA');
    expect(wordExercise.allowedLetters, 'ASDFJKLÉ');
    final invalid = readData('data/lessons/home_row_words.json');
    invalid['allowedLetters'] = 'AJ';
    expect(() => TypingExercise.fromJson(invalid), throwsFormatException);
    expect(
      () => MenuNode.fromJson({'id': 'bad', 'title': 'Empty'}),
      throwsFormatException,
    );
  });
  test('explicit progression validates references and is independent of menu nesting', () {
    final catalog = MenuCatalog.fromJson(readData('data/menu.json'));
    expect(catalog.nextActivity('home_row_letters')?.id, 'home_row_words');
    expect(
      catalog.nextActivity('home_row_words')?.command,
      MenuCommand.nextLesson,
    );
    expect(catalog.nextActivity('challenge_easy'), isNull);
    expect(catalog.routeTo('home_row_words'), isNotNull);
    final json = readData('data/menu.json');
    json['progression'] = [
      ['missing'],
    ];
    expect(() => MenuCatalog.fromJson(json), throwsFormatException);
    json['progression'] = [
      ['home_row_letters', 'home_row_letters'],
    ];
    expect(() => MenuCatalog.fromJson(json), throwsFormatException);
  });

  test(
    'audio generator and Dart agree on targets and generated word asset names',
    () async {
      final texts = [
        '123',
        'Anna 123 almát',
        '0640494949',
        '„Anna”, almát! 123',
      ];
      final process = await Process.run('python3', [
        '-c',
        'import json,sys; from tool.generate_audio import typing_words; print(json.dumps([typing_words(t) for t in json.loads(sys.argv[1])]))',
        jsonEncode(texts),
      ], workingDirectory: '../backend');
      expect(process.exitCode, 0, reason: process.stderr.toString());
      final generated = (jsonDecode(process.stdout as String) as List)
          .map((words) => (words as List).cast<String>())
          .toList();
      for (var i = 0; i < texts.length; i++) {
        expect(TypingUnit(id: 'test', text: texts[i]).words, generated[i]);
      }
      final generatedAssets = await Process.run('python3', [
        '-c',
        'import json; from tool.generate_audio import speech_texts; print(json.dumps(["assets/audio/"+n+".wav" for n,_ in speech_texts()]))',
      ], workingDirectory: '../backend');
      expect(
        generatedAssets.exitCode,
        0,
        reason: generatedAssets.stderr.toString(),
      );
      final assets = (jsonDecode(generatedAssets.stdout as String) as List)
          .cast<String>()
          .toSet();
      final catalog = MenuCatalog.fromJson(readData('data/menu.json'));
      for (final node in catalog.root.descendants) {
        if (node.activity case final ref?) {
          final exercise = ExerciseDefinition.fromJson(readData(ref.content));
          expect(assets, containsAll(exercise.audioAssets));
        }
      }
    },
  );
}
