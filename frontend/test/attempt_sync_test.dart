import 'dart:convert';
import 'dart:io';

import 'package:blind_typing/api/attempt_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for snapshot');
}

void main() {
  test(
    'uploads snapshots and recovers unfinished attempts after restart',
    () async {
      String? data;
      Future<String?> read(String key) async => data;
      Future<void> write(String key, String value) async {
        data = value;
      }

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, dynamic>>[];
      final sub = server.listen((request) async {
        received.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.statusCode = 200;
        await request.response.close();
      });
      final baseUrl = 'http://127.0.0.1:${server.port}';
      final sync = AttemptSync.withStorage(
        read: read,
        write: write,
        baseUrl: baseUrl,
      );
      await sync.initialize();
      sync.save({
        'id': 'abc',
        'revision': 0,
        'status': 'in_progress',
        'sampled_at': '2026-01-01T10:00:00Z',
      });
      await waitFor(
        () =>
            received.isNotEmpty &&
            (jsonDecode(data!)['pending'] as Map).isEmpty,
      );
      expect((jsonDecode(data!)['active'] as Map).containsKey('abc'), isTrue);
      sync.dispose();
      final restarted = AttemptSync.withStorage(
        read: read,
        write: write,
        baseUrl: baseUrl,
      );
      await restarted.initialize();
      await waitFor(() => received.length == 2);
      expect(received.last['status'], 'interrupted');
      expect(received.last['revision'], 1);
      expect(received.last['ended_at'], '2026-01-01T10:00:00Z');
      restarted.dispose();
      await sub.cancel();
      await server.close(force: true);
    },
  );
}
