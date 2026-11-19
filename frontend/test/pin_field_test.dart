import 'package:blind_typing/models/pin_update_result.dart';
import 'package:blind_typing/screens/pin_change_screen.dart';
import 'package:blind_typing/services/soloud_audio_service.dart';
import 'package:blind_typing/widgets/pin_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

void main() {
  const linux = TargetPlatformVariant({TargetPlatform.linux});
  testWidgets('login submits four or six masked digits only on request', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final submissions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 272,
            child: PinField(
              label: 'PIN-kód',
              hint: '4 vagy 6 számjegy',
              length: 6,
              controller: controller,
              autofocus: true,
              onSubmit: () => submissions.add(controller.text),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final editable = find.byType(EditableText);
    expect(editable, findsOneWidget);
    final input = tester.widget<Pinput>(find.byType(Pinput));
    expect(input.autofillHints, isNull);
    expect(input.defaultPinTheme!.width, closeTo((272 - 5 * 8) / 6, 0.01));
    expect(input.defaultPinTheme!.height, 48);
    expect(
      tester.widget<Text>(find.text('4 vagy 6 számjegy')).style!.fontSize,
      24,
    );
    await tester.enterText(editable, '0123');
    await tester.pump();
    final field = tester.getSemantics(find.bySemanticsLabel('PIN-kód'));
    final data = field.getSemanticsData();
    expect(data.flagsCollection.isTextField, isTrue);
    expect(data.flagsCollection.isObscured, isTrue);
    expect(data.hint, '4 vagy 6 számjegy');
    expect(data.value, isNot(contains('0123')));
    expect(submissions, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(submissions, ['0123']);
    await tester.enterText(editable, '456789');
    expect(submissions, ['0123']);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(submissions, ['0123', '456789']);
    await tester.showKeyboard(editable);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submissions, ['0123', '456789', '456789']);
  }, variant: linux);

  for (final (setupRequired, pin) in [(true, '0123'), (false, '123456')]) {
    testWidgets('PIN form preserves keyboard order for ${pin.length} digits', (
      tester,
    ) async {
      final audio = _RecordingPinAudio();
      final submissions = <(String?, String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PinChangeScreen(
            pinLength: pin.length,
            setupRequired: setupRequired,
            audio: audio,
            onSave: (current, newPin, confirmation) async {
              submissions.add((current, newPin, confirmation));
              return PinUpdateResult.saved;
            },
            onCancel: () {},
          ),
        ),
      );
      await tester.pump();
      final inputs = find.byType(Pinput);
      expect(inputs, findsNWidgets(setupRequired ? 2 : 3));
      final pinTheme = tester.widget<Pinput>(inputs.first).defaultPinTheme!;
      expect(pinTheme.width, 96);
      expect(pinTheme.height, 96);
      expect(
        tester.widgetList<Pinput>(inputs).map((input) => input.length),
        everyElement(pin.length),
      );
      if (!setupRequired) {
        tester.testTextInput.enterText(pin);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      tester.testTextInput.enterText(pin);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      tester.testTextInput.enterText(pin);
      expect(submissions, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submissions, [(setupRequired ? null : pin, pin, pin)]);
      expect(
        audio.spoken,
        containsAllInOrder([
          'assets/audio/login_pin_${setupRequired ? 'setup' : 'change'}.wav',
          'assets/audio/login_pin_repeat.wav',
        ]),
      );
    }, variant: linux);
  }
}

class _RecordingPinAudio extends SoloudAudioService {
  final spoken = <String>[];

  @override
  Future<void> initializePinForm() async {}

  @override
  Future<void> speak(String asset) async => spoken.add(asset);

  @override
  void stopSpeech() {}
}
