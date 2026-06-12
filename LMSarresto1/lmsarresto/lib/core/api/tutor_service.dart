import 'api_client.dart';

class TutorService {
  /// Creates a tutor session. Requires script_id.
  static Future<Map<String, dynamic>> createSession({
    required String scriptId,
    String learnerId = 'learner',
    int currentModule = 1,
    int currentLesson = 1,
  }) async {
    final data = await ApiClient.post('/api/v1/tutor/session', {
      'script_id': scriptId,
      'learner_id': learnerId,
      'current_module': currentModule,
      'current_lesson': currentLesson,
    });
    return data as Map<String, dynamic>;
  }

  /// Sends a chat message. Returns {session_id, reply, history_length}.
  static Future<Map<String, dynamic>> chat(String sessionId, String message) async {
    final data = await ApiClient.post('/api/v1/tutor/session/$sessionId/chat', {
      'message': message,
    });
    return data as Map<String, dynamic>;
  }

  /// Marks current lesson complete → returns checkpoint quiz questions.
  static Future<Map<String, dynamic>> completeLesson(String sessionId) async {
    final data = await ApiClient.post('/api/v1/tutor/session/$sessionId/complete-lesson', {});
    return data as Map<String, dynamic>;
  }

  /// Submits an answer to a quiz question. Returns {correct, explanation, checkpoint_complete, checkpoint_score}.
  static Future<Map<String, dynamic>> submitAnswer(
      String sessionId, String questionId, String answer) async {
    final data = await ApiClient.post('/api/v1/tutor/session/$sessionId/answer', {
      'question_id': questionId,
      'answer': answer,
    });
    return data as Map<String, dynamic>;
  }

  /// Advances to the next lesson. Returns {action, current_module, current_lesson, lesson_title}.
  static Future<Map<String, dynamic>> nextLesson(String sessionId) async {
    final data = await ApiClient.post('/api/v1/tutor/session/$sessionId/next-lesson', {});
    return data as Map<String, dynamic>;
  }

  /// Generates a practice quiz (ungraded).
  static Future<Map<String, dynamic>> generateQuiz(String sessionId, {int numQuestions = 3}) async {
    final data = await ApiClient.post('/api/v1/tutor/session/$sessionId/quiz', {
      'num_questions': numQuestions,
    });
    return data as Map<String, dynamic>;
  }

  /// Gets full conversation history.
  static Future<Map<String, dynamic>> getHistory(String sessionId) async {
    final data = await ApiClient.get('/api/v1/tutor/session/$sessionId/history');
    return data as Map<String, dynamic>;
  }
}
