import 'package:dio/dio.dart';
import 'api_client.dart';
import '../../features/learner/lesson_player/interactive_question.dart';

class QuestionService {
  /// Generates AI questions for a lesson checkpoint from the backend.
  /// Returns an empty list if the lesson has no transcript or the API key isn't set.
  static Future<List<InteractiveQuestion>> generateForLesson({
    required String courseId,
    required String lessonId,
    int count = 3,
    int? timestampSecs,
  }) async {
    try {
      final resp = await apiClient.post(
        '/api/v1/questions/generate',
        data: {
          'course_id':      courseId,
          'lesson_id':      lessonId,
          'count':          count,
          if (timestampSecs != null) 'timestamp_secs': timestampSecs,
        },
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );

      final raw = (resp.data['questions'] as List? ?? []);
      return raw.map((q) => _fromJson(q as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      // 404 = lesson has no script yet; 503 = no API key — both are non-fatal
      if (e.response?.statusCode == 404 || e.response?.statusCode == 503) {
        return [];
      }
      rethrow;
    }
  }

  static InteractiveQuestion _fromJson(Map<String, dynamic> j) {
    final type = switch (j['type'] as String? ?? 'multipleChoice') {
      'trueFalse'      => QuestionType.trueFalse,
      'text'           => QuestionType.text,
      'voice'          => QuestionType.voice,
      _                => QuestionType.multipleChoice,
    };
    return InteractiveQuestion(
      type:         type,
      prompt:       j['prompt'] as String,
      options:      (j['options'] as List? ?? []).cast<String>(),
      correctIndex: j['correct_index'] as int?,
    );
  }
}
