import 'dart:convert';
import 'dart:io';

import 'package:blind_typing/api/attempt_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() test) async {
  for (var i = 0; i < 200; i++) {
    if (test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out');
}

void main() {
  test('late completion is retained as interrupted and announced', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final statuses = <String>[];
    String? data;
    final subscription = server.listen((request) async {
      final snapshot = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      statuses.add(snapshot['status'] as String);
      if (snapshot['status'] == 'completed') {
        request.response.statusCode = 409;
        request.response.write('{"detail":"deadline_expired"}');
      }
      await request.response.close();
    });
    final sync = AttemptSync.withStorage(
      read: (_) async => data,
      write: (_, value) async {
        data = value;
      },
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    await sync.initialize();
    sync.save({
      'id': 'abc',
      'activity_id': 'homework_${'a' * 32}',
      'activity_type': 'homework',
      'revision': 1,
      'status': 'completed',
      'started_at': '2026-01-01T00:00:00Z',
      'ended_at': '2026-01-01T00:01:00Z',
    });
    await waitFor(
      () =>
          statuses.length == 2 && (jsonDecode(data!)['pending'] as Map).isEmpty,
    );
    expect(statuses, ['completed', 'interrupted']);
    expect(sync.homeworkEvents.value?.status, 'expired');
    sync.dispose();
    await subscription.cancel();
    await server.close(force: true);
  });
}
