import 'api_client.dart';
import 'models.dart';

class VideoService {
  static Future<String> renderLesson({
    required String scriptId,
    required int moduleNumber,
    required int lessonNumber,
    String lang = 'en',
    String style = 'animated_scene',
  }) async {
    final data = await ApiClient.post('/api/v1/video/render', {
      'script_id': scriptId,
      'module_number': moduleNumber,
      'lesson_number': lessonNumber,
      'lang': lang,
      'style': style,
    });
    return (data as Map<String, dynamic>)['render_id'] as String;
  }

  static Future<String> renderItem({
    required String scriptId,
    required int itemIndex,
    String lang = 'en',
    String style = 'animated_scene',
  }) async {
    final data = await ApiClient.post('/api/v1/video/render', {
      'script_id': scriptId,
      'item_index': itemIndex,
      'lang': lang,
      'style': style,
    });
    return (data as Map<String, dynamic>)['render_id'] as String;
  }

  static Future<VideoRender> getRenderStatus(String renderId) async {
    final data = await ApiClient.get('/api/v1/video/renders/$renderId');
    return VideoRender.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<VideoRender>> getScriptRenders(String scriptId) async {
    final data = await ApiClient.get('/api/v1/video/scripts/$scriptId/renders');
    final renders = (data as Map<String, dynamic>)['renders'] as List? ?? [];
    return renders.map((r) => VideoRender.fromJson(r as Map<String, dynamic>)).toList();
  }

  static String downloadUrl(String renderId) =>
      ApiClient.downloadUrl('/api/v1/video/renders/$renderId/download');

  static Future<List<Map<String, dynamic>>> getSupportedLanguages() async {
    final data = await ApiClient.get('/api/v1/video/languages');
    return List<Map<String, dynamic>>.from(data as List? ?? []);
  }
}
