import 'package:dio/dio.dart';
import '../../data/models/course.dart';
import '../../core/widgets/course_thumb.dart';
import 'api_client.dart';

class CourseService {
  // ── Library ────────────────────────────────────────────────────────────────

  static Future<List<Course>> listLibrary() async {
    final resp = await apiClient.get('/api/v1/courses/library');
    final scripts = resp.data['scripts'] as List;
    return scripts
        .map((s) => _courseFromApi(s as Map<String, dynamic>))
        .toList();
  }

  // ── Generation ─────────────────────────────────────────────────────────────

  static Future<String> generateCourse({
    required String sourceFile,
    String? courseTitle,
    String targetAudience = 'learners',
    String? instructions,
    bool useKnowledgeBase = true,
    String courseFormat = 'standard',
    String language = 'English',
    String durationRange = '60-90 minutes',
  }) async {
    final resp = await apiClient.post('/api/v1/courses/generate', data: {
      'source_file': sourceFile,
      if (courseTitle != null && courseTitle.isNotEmpty)
        'course_title': courseTitle,
      'target_audience': targetAudience,
      if (instructions != null && instructions.isNotEmpty)
        'instructions': instructions,
      'use_knowledge_base': useKnowledgeBase,
      'course_format': courseFormat,
      'language': language,
      'duration_range': durationRange,
    });
    return resp.data['job_id'] as String;
  }

  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final resp = await apiClient.get('/api/v1/courses/jobs/$jobId');
    return resp.data as Map<String, dynamic>;
  }

  /// Fetch a full library entry including the complete course_script.
  /// Returns an empty map when the course doesn't exist (404) so callers
  /// can fall back to mock data without entering an error state.
  static Future<Map<String, dynamic>> getCourseDetail(
      String scriptId) async {
    try {
      final resp = await apiClient.get('/api/v1/courses/library/$scriptId');
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {};
      rethrow;
    }
  }

  /// Rename a course. Fetches the existing script body first so the PATCH
  /// doesn't clobber it (the backend requires course_script in the body).
  static Future<void> updateCourseTitle(
      String scriptId, String newTitle) async {
    final detail = await getCourseDetail(scriptId);
    final existingScript =
        detail['course_script'] as Map<String, dynamic>? ?? {};
    await apiClient.patch('/api/v1/courses/library/$scriptId', data: {
      'course_script': existingScript,
      'course_title': newTitle,
    });
  }

  /// Permanently delete a course script from the library.
  static Future<void> deleteScript(String scriptId) async {
    await apiClient.delete('/api/v1/courses/library/$scriptId');
  }

  /// Save the assessment configuration for a course (num questions, pass %, etc.).
  static Future<void> saveAssessmentConfig(
    String scriptId, {
    int numQuestions = 5,
    int passPct      = 70,
    int timeMin      = 30,
    int retakes      = 3,
  }) async {
    await apiClient.patch(
      '/api/v1/courses/library/$scriptId/assessment-config',
      data: {
        'num_questions': numQuestions,
        'pass_pct':      passPct,
        'time_min':      timeMin,
        'retakes':       retakes,
      },
    );
  }

  /// Publish or save as draft.
  static Future<void> publishCourse(
    String scriptId, {
    String publishMode      = 'now',
    bool   notifyLearners   = true,
    bool   requireCompletion = true,
    String assignTo         = 'all',
  }) async {
    await apiClient.post(
      '/api/v1/courses/library/$scriptId/publish',
      data: {
        'published':          publishMode != 'draft',
        'publish_mode':       publishMode,
        'notify_learners':    notifyLearners,
        'require_completion': requireCompletion,
        'assign_to':          assignTo,
      },
    );
  }

  /// Convert a full library-detail response (from getCourseDetail) to a Course.
  static Course courseFromDetail(Map<String, dynamic> detail) =>
      _courseFromApi(detail);

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Course _courseFromApi(Map<String, dynamic> s) {
    final scriptId = s['script_id'] as String;
    return Course(
      id: scriptId,
      title: s['course_title'] as String,
      desc: s['target_audience'] as String? ?? '',
      cat: _categoryFromAudience(s['target_audience'] ?? ''),
      style: CourseStyle.animated,
      status: 'published',
      level: 'Intermediate',
      lessons: (s['total_lessons'] as num?)?.toInt() ?? 0,
      mins: (s['estimated_duration_min'] as num?)?.toInt() ?? 0,
      progress: 0,
      learners: 0,
      rating: 0.0,
      certified: false,
      // short readable code derived from the UUID
      code: scriptId.replaceAll('-', '').substring(0, 8).toUpperCase(),
    );
  }

  static String _categoryFromAudience(String audience) {
    final a = audience.toLowerCase();
    if (a.contains('field') || a.contains('worker')) return 'FIELD SAFETY';
    if (a.contains('supervisor') || a.contains('manager')) return 'LEADERSHIP';
    if (a.contains('safety') || a.contains('officer')) return 'SAFETY MANAGEMENT';
    if (a.contains('new') || a.contains('onboard')) return 'ONBOARDING';
    return 'TRAINING';
  }
}
