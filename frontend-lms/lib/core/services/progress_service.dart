import 'api_client.dart';

class Recommendation {
  final String type;      // "review_lesson" | "weak_topic"
  final String message;
  final int? module;
  final int? lesson;
  final String? topic;
  final double? score;
  final double? accuracy;

  const Recommendation({
    required this.type,
    required this.message,
    this.module,
    this.lesson,
    this.topic,
    this.score,
    this.accuracy,
  });

  factory Recommendation.fromJson(Map<String, dynamic> j) => Recommendation(
        type:     j['type'] as String,
        message:  j['message'] as String,
        module:   j['module'] as int?,
        lesson:   j['lesson'] as int?,
        topic:    j['topic'] as String?,
        score:    (j['score'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
      );
}

class ProgressService {
  static Future<void> recordLessonStart({
    required String learnerId,
    required String courseId,
    required int moduleIdx,
    required int lessonIdx,
  }) async {
    await apiClient.post(
      '/api/v1/progress/$learnerId/course/$courseId/lesson-start',
      data: {'module_idx': moduleIdx, 'lesson_idx': lessonIdx},
    );
  }

  static Future<void> recordLessonComplete({
    required String learnerId,
    required String courseId,
    required int moduleIdx,
    required int lessonIdx,
    double? score,
  }) async {
    await apiClient.post(
      '/api/v1/progress/$learnerId/course/$courseId/lesson-complete',
      data: {
        'module_idx': moduleIdx,
        'lesson_idx': lessonIdx,
        if (score != null) 'score': score,
      },
    );
  }

  static Future<void> recordQuizAttempt({
    required String learnerId,
    required String courseId,
    required int moduleIdx,
    required int lessonIdx,
    required String questionId,
    required String questionText,
    required String learnerAnswer,
    required String correctAnswer,
    required bool isCorrect,
    String topicTag = '',
    String quizType = 'lesson_checkpoint',
  }) async {
    await apiClient.post(
      '/api/v1/progress/$learnerId/course/$courseId/quiz-attempt',
      data: {
        'module_idx':     moduleIdx,
        'lesson_idx':     lessonIdx,
        'question_id':    questionId,
        'question_text':  questionText,
        'learner_answer': learnerAnswer,
        'correct_answer': correctAnswer,
        'is_correct':     isCorrect,
        'topic_tag':      topicTag,
        'quiz_type':      quizType,
      },
    );
  }

  static Future<List<Recommendation>> getRecommendations(
    String learnerId,
    String courseId,
  ) async {
    final resp = await apiClient.get(
      '/api/v1/progress/$learnerId/recommendations',
      queryParameters: {'course_id': courseId},
    );
    final list = resp.data as List;
    return list
        .map((r) => Recommendation.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
