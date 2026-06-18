import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/assessment_service.dart';
import '../../core/services/course_service.dart';
import '../../core/services/document_service.dart';
import '../../core/services/learner_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/progress_service.dart';
import '../../core/services/tutor_service.dart';
import '../../core/services/video_service.dart';
import '../models/course.dart';
import '../models/learner.dart';
import '../models/lesson.dart' show CourseLesson;
import '../models/notification_model.dart';

// ── Course library (list) ─────────────────────────────────────────────────────
final libraryProvider =
    FutureProvider.autoDispose<List<Course>>((ref) async {
  return CourseService.listLibrary();
});

// ── Course detail (full script) ───────────────────────────────────────────────
final courseDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, scriptId) => CourseService.getCourseDetail(scriptId),
);

// ── Course lessons parsed from real script ────────────────────────────────────
// Calls getCourseDetail and converts modules[].lessons[] → CourseLesson list.
// Lesson IDs: 'm{moduleNum}l{lessonNum}' e.g. 'm1l1', 'm2l3'.
final courseLessonsProvider =
    FutureProvider.autoDispose.family<List<CourseLesson>, String>(
  (ref, courseId) async {
    final detail = await CourseService.getCourseDetail(courseId);
    final script = detail['course_script'] as Map<String, dynamic>? ?? {};
    final modules = script['modules'] as List? ?? [];
    final lessons = <CourseLesson>[];

    if (modules.isNotEmpty) {
      // Standard generated course: modules → lessons
      for (final mod in modules) {
        final modMap = mod as Map<String, dynamic>;
        final moduleNum = (modMap['module_number'] as num).toInt();
        final moduleTitle =
            modMap['module_title'] as String? ?? 'Module $moduleNum';
        final rawLessons = modMap['lessons'] as List? ?? [];
        for (final les in rawLessons) {
          final lesMap = les as Map<String, dynamic>;
          final lessonNum = (lesMap['lesson_number'] as num).toInt();
          lessons.add(CourseLesson(
            id: 'm${moduleNum}l$lessonNum',
            courseId: courseId,
            module: moduleTitle,
            moduleNum: moduleNum,
            title: lesMap['lesson_title'] as String? ?? 'Lesson $lessonNum',
            durationSecs:
                ((lesMap['duration_minutes'] as num?)?.toInt() ?? 0) * 60,
            narrationScript: lesMap['narration_script'] as String?,
          ));
        }
      }
    } else {
      // Custom / blueprint course: flat items list (module=1, lesson=index+1)
      final items = script['items'] as List? ?? [];
      for (int i = 0; i < items.length; i++) {
        final item = items[i] as Map<String, dynamic>;
        final narration = item['narration'] as String? ??
            item['narration_script'] as String?;
        lessons.add(CourseLesson(
          id: 'm1l${i + 1}',
          courseId: courseId,
          module: 'Module 1',
          moduleNum: 1,
          title: item['title'] as String? ?? 'Lesson ${i + 1}',
          durationSecs:
              ((item['estimated_time_min'] as num?)?.toInt() ?? 0) * 60,
          narrationScript: narration,
        ));
      }
    }
    return lessons;
  },
);

// ── Documents ─────────────────────────────────────────────────────────────────
final documentsApiProvider =
    FutureProvider.autoDispose<List<DocumentInfo>>((ref) async {
  return DocumentService.listDocuments();
});

// ── Refreshable documents notifier ───────────────────────────────────────────
class DocumentsNotifier
    extends AutoDisposeAsyncNotifier<List<DocumentInfo>> {
  @override
  Future<List<DocumentInfo>> build() => DocumentService.listDocuments();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(DocumentService.listDocuments);
  }
}

final documentsNotifierProvider = AsyncNotifierProvider.autoDispose<
    DocumentsNotifier, List<DocumentInfo>>(DocumentsNotifier.new);

// ── Learner identity ──────────────────────────────────────────────────────────
// No auth yet — fixed learner ID. Replace with real auth when available.
final learnerIdProvider = StateProvider<String>((ref) => 'ariba@arresto.in');

// ── Active tutor sessions ─────────────────────────────────────────────────────
// Maps courseId → sessionId. Survives navigation within the app session.
final tutorSessionMapProvider =
    StateProvider<Map<String, String>>((ref) => {});

// ── Tutor session (legacy single holder kept for compatibility) ───────────────
final tutorSessionProvider =
    StateProvider.autoDispose<TutorSession?>((ref) => null);

// ── Assessment quiz from tutor session ───────────────────────────────────────
// Generates AI quiz questions for a course. Requires an active tutor session
// (created when the learner enters a lesson in that course).
final tutorQuizProvider =
    FutureProvider.autoDispose.family<List<TutorQuizQuestion>, String>(
  (ref, courseId) async {
    final sessionMap = ref.watch(tutorSessionMapProvider);
    final sessionId = sessionMap[courseId];
    if (sessionId == null) {
      throw Exception(
          'Start a lesson in this course before taking the assessment.');
    }
    return TutorService.generateQuiz(sessionId);
  },
);

// ── Last completed assessment result ─────────────────────────────────────────
// Populated by AssessmentQuizScreen on submit; read by result + review screens.
class QuizResult {
  final int correct;
  final int total;
  final int score;           // 0-100
  final int elapsedSeconds;
  final int passPct;         // pass threshold from course config
  final Map<String, String> answers;        // questionId → selected option key
  final Map<String, String> correctAnswers; // questionId → correct option key
  final Map<String, String> explanations;   // questionId → explanation text
  final List<AssessmentQuestion> questions; // full question list for review

  const QuizResult({
    required this.correct,
    required this.total,
    required this.score,
    this.elapsedSeconds = 0,
    this.passPct = 70,
    this.answers = const {},
    this.correctAnswers = const {},
    this.explanations = const {},
    this.questions = const [],
  });
}

final quizResultsProvider = StateProvider<QuizResult?>((ref) => null);

// ── Assessment questions (from course instructions + script) ──────────────────
// Generated by the backend from the admin's instructions (which contain the quiz)
// and cached in the DB. No tutor session required.
final assessmentQuestionsProvider =
    FutureProvider.autoDispose.family<List<AssessmentQuestion>, String>(
  (ref, courseId) => AssessmentService.getQuestions(courseId),
);

// ── Assessment attempt history (per-course) ───────────────────────────────────
final assessmentAttemptsProvider =
    FutureProvider.autoDispose.family<List<AssessmentAttempt>, String>(
  (ref, courseId) {
    final learnerId = ref.read(learnerIdProvider);
    return AssessmentService.getAttempts(courseId, learnerId: learnerId);
  },
);

// ── Assessment history (all courses) ─────────────────────────────────────────
// Used by the Assessments tab to show the learner's full attempt history.
final assessmentHistoryProvider =
    FutureProvider.autoDispose<List<AssessmentHistoryItem>>((ref) {
  final learnerId = ref.read(learnerIdProvider);
  return AssessmentService.getAllAttempts(learnerId);
});

// ── Video renders for a course ───────────────────────────────────────────────
// Fetches all render jobs for a course script. Returns empty list on error.
final videoRendersProvider =
    FutureProvider.autoDispose.family<List<VideoRenderJob>, String>(
  (ref, scriptId) async {
    try {
      return await VideoService.listRenders(scriptId);
    } catch (_) {
      return const [];
    }
  },
);

// ── Learner profile ───────────────────────────────────────────────────────────
final profileProvider =
    FutureProvider.autoDispose.family<ProfileData, String>(
  (ref, learnerId) => LearnerService.getProfile(learnerId),
);

// ── Admin: learners list ──────────────────────────────────────────────────────
final learnersApiProvider =
    FutureProvider.autoDispose<List<Learner>>(
  (ref) => LearnerService.listLearners(),
);

// ── Admin: single learner detail ──────────────────────────────────────────────
final learnerDetailApiProvider =
    FutureProvider.autoDispose.family<Learner, String>(
  (ref, learnerId) => LearnerService.getLearnerDetail(learnerId),
);

// ── Analytics overview ────────────────────────────────────────────────────────
final analyticsOverviewProvider =
    FutureProvider.autoDispose<AnalyticsOverview>(
  (ref) => AnalyticsService.getOverview(),
);

// ── Notifications (real API) ──────────────────────────────────────────────────
// recipientId is the learner's ID for learner notifications, or 'admin' for
// admin-wide notifications. The header passes the correct value based on role.
final notificationsProvider =
    FutureProvider.autoDispose.family<List<NotificationModel>, String>(
  (ref, recipientId) => NotificationService.list(recipientId),
);

// ── Adaptive recommendations for a course ────────────────────────────────────
// Derived from weak_topics and lesson checkpoint scores. Returns an empty list
// when the learner has no history yet (not an error state).
final recommendationsProvider =
    FutureProvider.autoDispose.family<List<Recommendation>, String>(
  (ref, courseId) async {
    final learnerId = ref.read(learnerIdProvider);
    try {
      return await ProgressService.getRecommendations(learnerId, courseId);
    } catch (_) {
      return const [];
    }
  },
);
