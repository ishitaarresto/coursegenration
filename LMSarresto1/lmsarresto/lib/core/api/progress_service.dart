import 'api_client.dart';

class ProgressService {
  static Future<Map<String, dynamic>> getCourseProgress(
      String learnerId, String courseId) async {
    final data = await ApiClient.get('/api/v1/progress/$learnerId/course/$courseId');
    return data as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getRecommendations(
      String learnerId, String courseId) async {
    final data = await ApiClient.get(
        '/api/v1/progress/$learnerId/recommendations?course_id=$courseId');
    return data as List? ?? [];
  }
}
