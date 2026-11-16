import 'package:blind_typing/models/area.dart';
import 'package:blind_typing/screens/area_selection_screen.dart';
import 'package:blind_typing/models/menu.dart';

import 'support/content_fixtures.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

void main() {
  test('role hierarchy and direct student entry', () {
    expect(areasForRole(UserRole.admin), [
      AppArea.admin,
      AppArea.trainer,
      AppArea.student,
    ]);
    expect(areasForRole(UserRole.trainer), [AppArea.trainer, AppArea.student]);
    expect(areasForRole(UserRole.student), [AppArea.student]);
    expect(initialAreaForRole(UserRole.student), AppArea.student);
    expect(initialAreaForRole(UserRole.trainer), isNull);
    expect(initialAreaForRole(UserRole.admin), isNull);
  });

  test('student menu can include a return command before logout', () {
    final data = readData('data/menu.json');
    final root = data['root'] as Map<String, dynamic>;
    final children = root['children'] as List<dynamic>;
    children.insert(children.length - 1, {
      'id': 'area_selector',
      'title': 'Vissza a területválasztóhoz',
      'command': 'areaSelector',
    });
    final catalog = MenuCatalog.fromJson(data);
    expect(
      catalog.root.children[catalog.root.children.length - 2].command,
      MenuCommand.areaSelector,
    );
    expect(catalog.root.children.last.command, MenuCommand.logout);
  });

  testWidgets('trainer selects student area using keyboard and speech', (
    tester,
  ) async {
    final audio = FakeAudioService();
    AppArea? selected;
    await tester.pumpWidget(
      AreaSelectionScreen(
        role: UserRole.trainer,
        audio: audio,
        onSelect: (area) => selected = area,
        onClose: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Adminisztrátor'), findsNothing);
    expect(find.text('Oktató'), findsOneWidget);
    expect(find.text('Tanuló'), findsOneWidget);
    expect(audio.spoken, contains('assets/audio/menu_area_trainer.wav'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(audio.spoken.last, 'assets/audio/menu_area_student.wav');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, AppArea.student);
  });
}
