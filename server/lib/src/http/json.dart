import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Error mapped to a JSON response by [errorMiddleware].
class ApiException implements Exception {
  ApiException(this.status, this.code, [String? message])
      : message = message ?? code;

  final int status;
  final String code;
  final String message;

  static ApiException badRequest(String msg) =>
      ApiException(400, 'bad_request', msg);
  static ApiException unauthorized([String msg = 'Authentication required']) =>
      ApiException(401, 'unauthorized', msg);
  static ApiException notFound([String msg = 'Not found']) =>
      ApiException(404, 'not_found', msg);
  static ApiException conflict(String msg) => ApiException(409, 'conflict', msg);
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Future<Map<String, dynamic>> readJson(Request req) async {
  final body = await req.readAsString();
  if (body.isEmpty) return {};
  try {
    final v = jsonDecode(body);
    if (v is Map<String, dynamic>) return v;
  } on FormatException {
    // fallthrough
  }
  throw ApiException.badRequest('Body must be a JSON object');
}

T field<T>(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is T) return v;
  throw ApiException.badRequest('Field "$key" is missing or invalid');
}
