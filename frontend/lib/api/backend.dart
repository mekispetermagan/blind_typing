import 'dart:io';

const backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

Future<HttpClientResponse> backendGet(String path, {String? etag}) async {
  final request = await _client.getUrl(Uri.parse('$backendUrl$path'));
  if (etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
  return request.close().timeout(const Duration(seconds: 30));
}
