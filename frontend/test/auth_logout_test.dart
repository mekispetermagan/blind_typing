import 'dart:convert';
import 'dart:io';

import 'package:blind_typing/api/auth_session.dart';
import 'package:blind_typing/api/backend.dart';
import 'package:blind_typing/models/area.dart';
import 'package:blind_typing/models/pin_update_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a student can confirm the same temporary PIN and change it later',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final updates = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        if (request.uri.path == '/api/auth/login') {
          request.response.write(
            jsonEncode({
              'token': 'student-token',
              'user_id': 1,
              'name': 'Student',
              'role': 'student',
              'pin_temporary': true,
            }),
          );
        } else if (request.uri.path == '/api/auth/pin') {
          updates.add(body);
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer student-token',
          );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      final auth = AuthSession(baseUrl: 'http://127.0.0.1:${server.port}');
      try {
        expect(await auth.login('student', '1234'), isTrue);
        expect(auth.pinTemporary, isTrue);
        expect(
          await auth.savePin(null, '123456', '123456'),
          PinUpdateResult.invalidNewPin,
        );
        expect(
          await auth.savePin(null, '1234', '4321'),
          PinUpdateResult.mismatch,
        );
        expect(updates, isEmpty);
        expect(await auth.savePin(null, '1234', '1234'), PinUpdateResult.saved);
        expect(auth.pinTemporary, isFalse);
        expect(
          await auth.savePin('1234', '0239', '0239'),
          PinUpdateResult.saved,
        );
        expect(updates, [
          {'new_pin': '1234'},
          {'current_pin': '1234', 'new_pin': '0239'},
        ]);
      } finally {
        auth.dispose();
        await server.close(force: true);
      }
    },
  );

  test('logout clears the client and revokes the active token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? revokedToken;
    final subscription = server.listen((request) async {
      if (request.uri.path == '/api/auth/login') {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'token': 'demo-token',
            'user_id': 1,
            'name': 'Test',
            'role': 'admin',
          }),
        );
      } else {
        expect(request.uri.path, '/api/auth/logout');
        revokedToken = request.headers.value(HttpHeaders.authorizationHeader);
      }
      await request.response.close();
    });
    final auth = AuthSession(baseUrl: 'http://127.0.0.1:${server.port}');
    try {
      expect(await auth.login('test', '123456'), isTrue);
      expect(auth.role, UserRole.admin);
      final logout = auth.logout();
      expect(auth.token, isNull);
      expect(auth.role, isNull);
      expect(backendToken, isNull);
      expect(auth.expired, isFalse);
      await logout;
      expect(revokedToken, 'Bearer demo-token');
    } finally {
      auth.dispose();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
