import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// Persists pending snapshots before delivery; latest revision wins per attempt.
class AttemptSync {
  AttemptSync(
    SharedPreferencesAsync preferences, {
    this.baseUrl = backendUrl,
    this.storageKey = _key,
    this.sessionToken,
  }) : _read = preferences.getString,
       _write = preferences.setString;
  AttemptSync.withStorage({
    required Future<String?> Function(String) read,
    required Future<void> Function(String, String) write,
    this.baseUrl = backendUrl,
    this.storageKey = _key,
    this.sessionToken,
  }) : _read = read,
       _write = write;
  final String baseUrl;
  final String storageKey;
  final String? sessionToken;
  bool _disposed = false;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  static const _key = 'pending_attempt_snapshots';
  final Map<String, Map<String, dynamic>> _pending = {};
  final Map<String, Map<String, dynamic>> _active = {};
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  Future<void> _writes = Future.value();
  Future<void>? _syncing;
  bool _loaded = false;
  Timer? _retry;

  Future<void> initialize() async {
    if (_loaded) return;
    final saved = await _read(storageKey);
    if (saved != null) {
      final decoded = jsonDecode(saved) as Map<String, dynamic>;
      final pending = Map<String, dynamic>.from(
        decoded['pending'] as Map? ?? {},
      );
      final active = Map<String, dynamic>.from(decoded['active'] as Map? ?? {});
      pending.addAll(active);
      for (final entry in pending.entries) {
        final snapshot = Map<String, dynamic>.from(entry.value as Map);
        if (snapshot['status'] == 'in_progress') {
          snapshot['status'] = 'interrupted';
          snapshot['ended_at'] =
              snapshot['sampled_at'] ??
              DateTime.now().toUtc().toIso8601String();
          snapshot['revision'] = (snapshot['revision'] as int) + 1;
        }
        _pending[entry.key] = snapshot;
      }
    }
    _loaded = true;
    await _persist();
    unawaited(_sync());
    if (_disposed) return;
    _retry ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_sync()),
    );
  }

  void save(Map<String, dynamic> snapshot) {
    final id = snapshot['id'] as String;
    _pending[id] = snapshot;
    if (snapshot['status'] == 'in_progress') {
      _active[id] = snapshot;
    } else {
      _active.remove(id);
    }
    unawaited(
      _persist().then((_) => _sync()).catchError((Object error) {
        developer.log('Could not save attempt', error: error);
      }),
    );
  }

  Future<void> _persist() {
    final json = jsonEncode({'pending': _pending, 'active': _active});
    final write = _writes.then((_) => _write(storageKey, json));
    _writes = write.catchError((Object error) {
      developer.log('Could not persist attempt queue', error: error);
    });
    return write;
  }

  Future<void> _sync() =>
      _syncing ??= _send().whenComplete(() => _syncing = null);

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _client.close(force: true);
  }

  Future<void> _send() async {
    while (!_disposed && _pending.isNotEmpty) {
      if (sessionToken != null && backendToken != sessionToken) return;
      final id = _pending.keys.first;
      final snapshot = _pending[id]!;
      try {
        final request = await _client.putUrl(
          Uri.parse('$baseUrl/api/attempts/$id'),
        );
        final token = sessionToken ?? backendToken;
        if (token != null)
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode(
            Map.of(snapshot)
              ..remove('id')
              ..remove('sampled_at'),
          ),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        await response.drain<void>();
        if (response.statusCode == 401 && token != null)
          onUnauthorized?.call(token);
        if (response.statusCode != 200) {
          throw StateError('Attempt upload: ${response.statusCode}');
        }
        if (_pending[id]?['revision'] == snapshot['revision']) {
          _pending.remove(id);
          await _persist();
        }
      } catch (error) {
        developer.log('Attempt upload will be retried', error: error);
        return;
      }
    }
  }
}
