import 'dart:convert';
import 'dart:io';

import 'backend.dart';

class AudioCache {
  AudioCache({Directory? root}) : _configuredRoot = root;

  final Directory? _configuredRoot;
  Directory? _root;
  String? _activityKey;

  Future<void> initialize() async {
    if (_root != null) return;
    final env = Platform.environment;
    final base = env['XDG_CACHE_HOME'] ?? '${env['HOME']}/.cache';
    final root = _configuredRoot ?? Directory('$base/blind_typing');
    final activity = Directory('${root.path}/activity');
    if (await activity.exists()) await activity.delete(recursive: true);
    await Directory('${root.path}/shared').create(recursive: true);
    await activity.create(recursive: true);
    _root = root;
  }

  Future<void> selectActivity(Set<String> assets) async {
    if (assets.isEmpty) return;
    await initialize();
    final sorted = assets.toList()..sort();
    final key = sorted.join('|');
    if (_activityKey == key) return;
    final directory = Directory('${_root!.path}/activity');
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
    _activityKey = key;
  }

  Future<String> get(String asset, {required bool shared}) async {
    await initialize();
    final name = asset.split('/').last;
    if (!RegExp(r'^[a-zA-Z0-9_]+\.(wav|mp3)$').hasMatch(name)) {
      throw FormatException('Invalid audio asset: $asset');
    }
    final file = File('${_root!.path}/${shared ? 'shared' : 'activity'}/$name');
    final tagFile = File('${file.path}.etag');
    if (!shared && await file.exists()) return file.path;
    final etag = await file.exists() && await tagFile.exists()
        ? await tagFile.readAsString()
        : null;
    final response = await backendGet('/api/audio/$name', etag: etag);
    if (response.statusCode == 304 && await file.exists()) {
      await response.drain<void>();
      return file.path;
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw StateError('Audio download failed: ${response.statusCode}');
    }
    final temporary = File('${file.path}.part');
    try {
      final sink = temporary.openWrite();
      await response.timeout(const Duration(seconds: 30)).pipe(sink);
      await temporary.rename(file.path);
      final tag = response.headers.value(HttpHeaders.etagHeader);
      if (tag != null) await tagFile.writeAsString(tag, encoding: utf8);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return file.path;
  }
}
