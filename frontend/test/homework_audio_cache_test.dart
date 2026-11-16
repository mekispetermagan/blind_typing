import 'dart:io';

import 'package:blind_typing/api/audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared speech is cached once but each homework is authorized',
    () async {
      final root = await Directory.systemTemp.createTemp('homework-cache-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final tags = <String?>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        tags.add(request.headers.value(HttpHeaders.ifNoneMatchHeader));
        request.response.headers.set(HttpHeaders.etagHeader, '"shared"');
        if (tags.last == '"shared"') {
          request.response.statusCode = 304;
        } else {
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      });
      final client = HttpClient();
      Future<HttpClientResponse> fetch(String path, {String? etag}) async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        if (etag != null)
          request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
        return request.close();
      }

      try {
        final cache = AudioCache(root: root, fetch: fetch);
        final hash = 'c' * 64;
        final first = await cache.get(
          'assets/audio/homework_audio_${'a' * 32}_$hash.wav',
          shared: false,
        );
        final second = await cache.get(
          'assets/audio/homework_audio_${'b' * 32}_$hash.wav',
          shared: false,
        );
        expect(first, second);
        expect(await File(first).readAsBytes(), [1, 2, 3]);
        expect(paths, [
          '/api/homeworks/${'a' * 32}/audio/$hash',
          '/api/homeworks/${'b' * 32}/audio/$hash',
        ]);
        expect(tags, [null, '"shared"']);
      } finally {
        client.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
