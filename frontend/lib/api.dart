import 'dart:convert';
import 'package:http/http.dart' as http;

class Api {
  Api({this.baseUrl = ''});
  final String baseUrl;

  Future<int> generateCourse(String content,
      {String mode = 'detailed', List<String> languages = const ['en']}) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/courses/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'content_text': content, 'mode': mode, 'languages': languages}),
    );
    if (r.statusCode != 200) throw Exception('generate failed: ${r.body}');
    return jsonDecode(r.body)['id'] as int;
  }

  Future<Map<String, dynamic>> getJob(int id) async {
    final r = await http.get(Uri.parse('$baseUrl/api/jobs/$id'));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCourse(int id) async {
    final r = await http.get(Uri.parse('$baseUrl/api/courses/$id'));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  String slidesUrl(int courseId, int lessonId) =>
      '$baseUrl/api/courses/$courseId/lessons/$lessonId/slides';

  Future<Map<String, dynamic>> renderVideo(int courseId, int lessonId,
      {String lang = 'en'}) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/courses/$courseId/lessons/$lessonId/render?lang=$lang'),
    );
    if (r.statusCode != 200) throw Exception('render failed: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getRenderStatus(int renderId) async {
    final r = await http.get(Uri.parse('$baseUrl/api/renders/$renderId/status'));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  String videoUrl(int courseId, int lessonId, {String lang = 'en'}) =>
      '$baseUrl/api/courses/$courseId/lessons/$lessonId/video?lang=$lang';
}
