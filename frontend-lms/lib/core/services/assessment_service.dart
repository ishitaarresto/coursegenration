import 'package:dio/dio.dart';
import 'api_client.dart';

class AssessmentQuestion {
  final String id;
  final String question;
  final Map<String, String> options;
  final String correctAnswer;
  final String explanation;
  final String type; // "mcq" | "true_false"

  const AssessmentQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    this.type = 'mcq',
  });

  // If backend doesn't send a type, infer it: two options whose values are
  // "true"/"false" (case-insensitive) are treated as a True/False question.
  static String _inferType(Map<String, String> opts) {
    if (opts.length == 2) {
      final vals = opts.values.map((v) => v.toLowerCase()).toSet();
      if (vals.containsAll({'true', 'false'})) return 'true_false';
    }
    return 'mcq';
  }

  factory AssessmentQuestion.fromJson(Map<String, dynamic> j) {
    final opts = (j['options'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as String));
    return AssessmentQuestion(
      id: j['id'] as String,
      question: j['question'] as String,
      options: opts,
      correctAnswer: j['correct_answer'] as String? ?? 'A',
      explanation: j['explanation'] as String? ?? '',
      type: j['type'] as String? ?? _inferType(opts),
    );
  }
}

class AssessmentAttempt {
  final String id;
  final int score;
  final int correct;
  final int total;
  final bool passed;
  final int elapsedSeconds;
  final double takenAt;

  const AssessmentAttempt({
    required this.id,
    required this.score,
    required this.correct,
    required this.total,
    required this.passed,
    required this.elapsedSeconds,
    required this.takenAt,
  });

  factory AssessmentAttempt.fromJson(Map<String, dynamic> j) {
    return AssessmentAttempt(
      id: j['id'] as String,
      score: (j['score'] as num).toInt(),
      correct: (j['correct'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      passed: j['passed'] as bool,
      elapsedSeconds: (j['elapsed_seconds'] as num? ?? 0).toInt(),
      takenAt: (j['taken_at'] as num).toDouble(),
    );
  }

  String get formattedDate {
    final dt = DateTime.fromMillisecondsSinceEpoch((takenAt * 1000).round());
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String get elapsedFormatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class AssessmentHistoryItem {
  final String id;
  final String courseId;
  final String courseTitle;
  final int score;
  final int correct;
  final int total;
  final bool passed;
  final int elapsedSeconds;
  final double takenAt;
  final int attemptNumber;
  final int totalAttempts;

  const AssessmentHistoryItem({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.score,
    required this.correct,
    required this.total,
    required this.passed,
    required this.elapsedSeconds,
    required this.takenAt,
    required this.attemptNumber,
    required this.totalAttempts,
  });

  factory AssessmentHistoryItem.fromJson(Map<String, dynamic> j) {
    return AssessmentHistoryItem(
      id:             j['id'] as String,
      courseId:       j['course_id'] as String,
      courseTitle:    j['course_title'] as String,
      score:          (j['score'] as num).toInt(),
      correct:        (j['correct'] as num).toInt(),
      total:          (j['total'] as num).toInt(),
      passed:         j['passed'] as bool,
      elapsedSeconds: (j['elapsed_seconds'] as num? ?? 0).toInt(),
      takenAt:        (j['taken_at'] as num).toDouble(),
      attemptNumber:  (j['attempt_number'] as num).toInt(),
      totalAttempts:  (j['total_attempts'] as num).toInt(),
    );
  }

  String get formattedDate {
    final dt = DateTime.fromMillisecondsSinceEpoch((takenAt * 1000).round());
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String get attemptLabel =>
      '$totalAttempts attempt${totalAttempts != 1 ? 's' : ''} · Taken $formattedDate';
}

class AssessmentService {
  // First-call generates via Claude (20-60 s); cached calls return instantly.
  // Per-request timeout overrides global Dio connectTimeout — on Flutter Web
  // connectTimeout maps to the XHR timeout (total duration, not TCP handshake).
  static Future<List<AssessmentQuestion>> getQuestions(
    String courseId, {
    bool regenerate = false,
  }) async {
    final resp = await apiClient.get(
      '/api/v1/courses/library/$courseId/assessment-questions',
      queryParameters: regenerate ? {'regenerate': 'true'} : null,
      options: Options(
        connectTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    final questions = resp.data['questions'] as List;
    return questions
        .map((q) => AssessmentQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAttempt({
    required String courseId,
    required String learnerId,
    required int score,
    required int correct,
    required int total,
    required bool passed,
    required int elapsedSeconds,
    required Map<String, String> answers,
  }) async {
    try {
      await apiClient.post(
        '/api/v1/courses/library/$courseId/assessment-attempts',
        data: {
          'learner_id': learnerId,
          'score': score,
          'correct': correct,
          'total': total,
          'passed': passed,
          'elapsed_seconds': elapsedSeconds,
          'answers': answers,
        },
      );
    } catch (_) {
      // Fire-and-forget — never block the result screen if this fails
    }
  }

  /// All attempts across every course for a learner — used by the Assessments tab.
  static Future<List<AssessmentHistoryItem>> getAllAttempts(
    String learnerId,
  ) async {
    final resp = await apiClient.get(
      '/api/v1/assessments/history',
      queryParameters: {'learner_id': learnerId},
    );
    final list = resp.data['attempts'] as List;
    return list
        .map((a) => AssessmentHistoryItem.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  static Future<List<AssessmentAttempt>> getAttempts(
    String courseId, {
    required String learnerId,
  }) async {
    final resp = await apiClient.get(
      '/api/v1/courses/library/$courseId/assessment-attempts',
      queryParameters: {'learner_id': learnerId},
    );
    final list = resp.data['attempts'] as List;
    return list
        .map((a) => AssessmentAttempt.fromJson(a as Map<String, dynamic>))
        .toList();
  }
}
