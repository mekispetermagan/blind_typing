import 'dart:io';

const backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

String? backendToken;
void Function(String token)? onUnauthorized;

final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

Future<HttpClientResponse> backendGet(String path, {String? etag}) async {
  final request = await _client.getUrl(Uri.parse('$backendUrl$path'));
  final token = backendToken;
  if (token != null)
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  if (etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
  final response = await request.close().timeout(const Duration(seconds: 30));
  if (response.statusCode == 401 && token != null) onUnauthorized?.call(token);
  return response;
}
