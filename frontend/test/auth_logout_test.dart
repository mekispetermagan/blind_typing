import 'dart:convert';
import 'dart:io';

import 'package:blind_typing/api/auth_session.dart';
import 'package:blind_typing/api/backend.dart';
import 'package:blind_typing/models/area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
