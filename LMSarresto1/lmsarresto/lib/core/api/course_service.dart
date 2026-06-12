import 'api_client.dart';
import 'models.dart';

class CourseService {
  static Future<List<LibraryItem>> listLibrary() async {
    final data = await ApiClient.get('/api/v1/courses/library');
    final scripts = data['scripts'] as List? ?? [];
    return scripts.map((s) => LibraryItem.fromJson(s as Map<String, dynamic>)).toList();
  }

  static Future<CourseScript> getScript(String scriptId) async {
    final data = await ApiClient.get('/api/v1/courses/library/$scriptId');
    return CourseScript.fromJson(data as Map<String, dynamic>);
  }

  static Future<String> generateCourse({
    required String sourceFile,
    String? courseTitle,
    String targetAudience = 'learners',
    String? instructions,
    bool useKnowledgeBase = false,
    String courseFormat = 'standard',
  }) async {
    if (instructions != null && instructions.isNotEmpty) {
      // Use multipart endpoint to avoid JSON escaping issues
      final fields = {
        'source_file': sourceFile,
        'instructions': instructions,
        'target_audience': targetAudience,
        'use_knowledge_base': useKnowledgeBase.toString(),
        'course_format': courseFormat,
        if (courseTitle != null) 'course_title': courseTitle,
      };
      final data = await ApiClient.postMultipart('/api/v1/courses/generate-blueprint', fields);
      return (data as Map<String, dynamic>)['job_id'] as String;
    } else {
      final body = <String, dynamic>{
        'source_file': sourceFile,
        'target_audience': targetAudience,
        'use_knowledge_base': useKnowledgeBase,
        'course_format': courseFormat,
        if (courseTitle != null && courseTitle.isNotEmpty) 'course_title': courseTitle,
      };
      final data = await ApiClient.post('/api/v1/courses/generate', body);
      return (data as Map<String, dynamic>)['job_id'] as String;
    }
  }

  static Future<JobStatus> getJobStatus(String jobId) async {
    final data = await ApiClient.get('/api/v1/courses/jobs/$jobId');
    return JobStatus.fromJson(data as Map<String, dynamic>);
  }

  static Future<Map<String, dynamic>> getRawScript(String scriptId) async {
    final data = await ApiClient.get('/api/v1/courses/library/$scriptId');
    return data as Map<String, dynamic>;
  }

  static Future<void> saveScript(
    String scriptId,
    Map<String, dynamic> courseScript, {
    String? courseTitle,
  }) async {
    final body = <String, dynamic>{'course_script': courseScript};
    if (courseTitle != null) body['course_title'] = courseTitle;
    await ApiClient.patch('/api/v1/courses/library/$scriptId', body);
  }

  static Future<void> deleteScript(String scriptId) async {
    await ApiClient.delete('/api/v1/courses/library/$scriptId');
  }
}
