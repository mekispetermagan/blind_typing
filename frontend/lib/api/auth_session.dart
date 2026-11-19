import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/area.dart';
import '../models/pin_update_result.dart';
import 'backend.dart';

class AuthSession extends ChangeNotifier {
  AuthSession({this.baseUrl = backendUrl});

  final String baseUrl;
  String? token;
  int? userId;
  String? identifier;
  String? name;
  UserRole? role;
  bool pinTemporary = false;
  int get pinLength => role == UserRole.student ? 4 : 6;
  bool expired = false;
  DateTime? _lastInteraction;
  DateTime? _lastReported;
  Timer? _timer;
  Timer? _idleTimer;
  bool _changed = false;
  bool _refreshing = false;
  static const idleLimit = Duration(minutes: 10);

  Future<bool> login(String identifier, String pin) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.postUrl(
          Uri.parse('$baseUrl/api/auth/login'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'identifier': identifier, 'pin': pin}));
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) return false;
        final data = jsonDecode(body) as Map<String, dynamic>;
        final authenticatedRole = UserRole.values.byName(
          data['role'] as String,
        );
        role = authenticatedRole;
        token = data['token'] as String;
        userId = data['user_id'] as int;
        this.identifier = identifier.trim().toLowerCase();
        name = data['name'] as String;
        pinTemporary = data['pin_temporary'] == true;
        expired = false;
        backendToken = token;
        onUnauthorized = _unauthorized;
        _lastInteraction = DateTime.now();
        _lastReported = _lastInteraction;
        _idleTimer?.cancel();
        _idleTimer = Timer(idleLimit, _expire);
        _changed = false;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
        notifyListeners();
        return true;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    }
  }

  Future<PinUpdateResult> savePin(
    String? currentPin,
    String newPin,
    String confirmation,
  ) async {
    final current = token;
    if (current == null) return PinUpdateResult.failed;
    if (newPin.length != pinLength || !RegExp(r'^[0-9]+$').hasMatch(newPin)) {
      return PinUpdateResult.invalidNewPin;
    }
    if (newPin != confirmation) return PinUpdateResult.mismatch;
    if (currentPin != null &&
        (currentPin.length != pinLength ||
            !RegExp(r'^[0-9]+$').hasMatch(currentPin))) {
      return PinUpdateResult.incorrectCurrentPin;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/api/auth/pin'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $current');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'new_pin': newPin, 'current_pin': ?currentPin}),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>().timeout(const Duration(seconds: 30));
      if (token != current) return PinUpdateResult.failed;
      switch (response.statusCode) {
        case 200:
          if (pinTemporary) {
            pinTemporary = false;
            notifyListeners();
          }
          return PinUpdateResult.saved;
        case 400:
          return PinUpdateResult.incorrectCurrentPin;
        case 401:
        case 409:
          _unauthorized(current);
          return PinUpdateResult.failed;
        default:
          return PinUpdateResult.failed;
      }
    } catch (_) {
      return PinUpdateResult.failed;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> logout() async {
    final current = token;
    if (current == null) return;
    _timer?.cancel();
    _idleTimer?.cancel();
    token = null;
    role = null;
    pinTemporary = false;
    backendToken = null;
    expired = false;
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/api/auth/logout'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $current');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>();
    } catch (_) {
      // Local logout still succeeds if the backend cannot be reached.
    } finally {
      client.close(force: true);
    }
  }

  void interaction() {
    if (token == null) return;
    if (DateTime.now().difference(_lastInteraction!) >= idleLimit) {
      _expire();
      return;
    }
    _lastInteraction = DateTime.now();
    _idleTimer?.cancel();
    _idleTimer = Timer(idleLimit, _expire);
    _changed = true;
    if (DateTime.now().difference(_lastReported!) >=
        const Duration(minutes: 9)) {
      unawaited(_tick());
    }
  }

  void _unauthorized(String usedToken) {
    if (token == usedToken) _expire();
  }

  void _expire() {
    _timer?.cancel();
    _idleTimer?.cancel();
    token = null;
    role = null;
    pinTemporary = false;
    backendToken = null;
    expired = true;
    notifyListeners();
  }

  Future<void> _tick() async {
    final current = token;
    if (current == null) return;
    if (DateTime.now().difference(_lastInteraction!) >= idleLimit) {
      _expire();
      return;
    }
    if (!_changed || _refreshing) return;
    _changed = false;
    final interactionTime = _lastInteraction!;
    _refreshing = true;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/api/auth/activity'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $current');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'occurred_at': interactionTime.toUtc().toIso8601String()}),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>();
      if (response.statusCode == 401) _unauthorized(current);
      if (response.statusCode == 200 && token == current)
        _lastReported = interactionTime;
      if (response.statusCode != 200 && token == current) _changed = true;
    } catch (_) {
      if (token == current) _changed = true;
    } finally {
      client.close(force: true);
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idleTimer?.cancel();
    backendToken = null;
    onUnauthorized = null;
    super.dispose();
  }
}
