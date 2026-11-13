import 'dart:io';

import 'package:blind_typing/api/audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retains current activity, replaces it for a new one, and clears it after restart', () async {
    final root = await Directory.systemTemp.createTemp('typing-cache-test');
    addTearDown(() => root.delete(recursive: true));
    final cache = AudioCache(root: root);
    await cache.initialize();
    final shared = File('${root.path}/shared/menu.wav');
    final activity = File('${root.path}/activity/word.wav');
    await shared.writeAsString('shared');
    await cache.selectActivity({'word'});
    await activity.writeAsString('activity');
    await cache.selectActivity({});
    await cache.selectActivity({'word'});
    expect(await activity.exists(), isTrue);
    await cache.selectActivity({'other'});
    expect(await activity.exists(), isFalse);
    expect(await shared.exists(), isTrue);
    await activity.writeAsString('leftover');
    await AudioCache(root: root).initialize();
    expect(await activity.exists(), isFalse);
    expect(await shared.exists(), isTrue);
  });
}
