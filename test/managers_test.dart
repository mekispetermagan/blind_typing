import 'dart:io';

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
        File(node.audioAsset).existsSync(),
        isTrue,
        reason: node.audioAsset,
      );
      final reference = node.activity;
      if (reference == null) continue;
      final exercise = ExerciseDefinition.fromJson(readData(reference.content));
      expect(exercise.type, reference.type);
      types.add(exercise.type);
      for (final audio in exercise.audioAssets) {
        expect(File(audio).existsSync(), isTrue, reason: audio);
      }
    }
    expect(types, ActivityType.values.toSet());
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
}
