import 'dart:convert';
import 'package:http/http.dart' as http;

const _kBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

class ApiClient {
  static const base = _kBase;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: _headers);
    _checkStatus(r);
    return jsonDecode(r.body);
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final r = await http.post(
      Uri.parse('$base$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    _checkStatus(r);
    return jsonDecode(r.body);
  }

  static Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async {
    final r = await http.patch(
      Uri.parse('$base$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    _checkStatus(r);
    return jsonDecode(r.body);
  }

  static Future<dynamic> delete(String path) async {
    final r = await http.delete(Uri.parse('$base$path'), headers: _headers);
    _checkStatus(r);
    return jsonDecode(r.body);
  }

  static Future<dynamic> postMultipart(
      String path, Map<String, String> fields, {String? fileField, List<int>? fileBytes, String? filename}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base$path'));
    req.fields.addAll(fields);
    if (fileField != null && fileBytes != null && filename != null) {
      req.files.add(http.MultipartFile.fromBytes(fileField, fileBytes, filename: filename));
    }
    final streamed = await req.send();
    final r = await http.Response.fromStream(streamed);
    _checkStatus(r);
    return jsonDecode(r.body);
  }

  static void _checkStatus(http.Response r) {
    if (r.statusCode >= 400) {
      Map detail;
      try { detail = jsonDecode(r.body); } catch (_) { detail = {}; }
      throw ApiException(r.statusCode, detail['detail']?.toString() ?? r.body);
    }
  }

  static String downloadUrl(String path) => '$base$path';
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}
