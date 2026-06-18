import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_state.dart';
import '../../features/shared/shell/learner_shell.dart';
import '../../features/shared/shell/admin_shell.dart';
import '../../features/learner/dashboard/learner_dashboard_screen.dart';
import '../../features/learner/catalog/course_catalog_screen.dart';
import '../../features/learner/my_courses/my_courses_screen.dart';
import '../../features/learner/assessments/assessments_screen.dart';
import '../../features/learner/course_detail/course_detail_screen.dart';
import '../../features/learner/lesson_player/lesson_player_screen.dart';
import '../../features/learner/assessment/assessment_intro_screen.dart';
import '../../features/learner/assessment/assessment_quiz_screen.dart';
import '../../features/learner/assessment/assessment_result_screen.dart';
import '../../features/learner/assessment/assessment_review_screen.dart';
import '../../features/learner/assessment/assessment_flashcards_screen.dart';
import '../../features/learner/certificates/certificates_screen.dart';
import '../../features/learner/support/support_screen.dart';
import '../../features/learner/profile/profile_screen.dart';
import '../../features/learner/resources/resources_screen.dart';
import '../../features/learner/arresto_ai/arresto_ai_screen.dart';
import '../../features/admin/dashboard/admin_dashboard_screen.dart';
import '../../features/admin/generator/generator_wizard.dart';
import '../../features/admin/learners/learners_screen.dart';
import '../../features/admin/learners/learner_detail_screen.dart';
import '../../features/admin/analytics/analytics_screen.dart';
import '../../features/admin/support/admin_support_screen.dart';
import '../../features/admin/support/ticket_detail_screen.dart';
import '../../features/admin/settings/settings_screen.dart';
import '../../features/admin/courses/all_courses_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/learner',
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/learner',
      ),
      ShellRoute(
        builder: (ctx, state, child) => LearnerShell(child: child),
        routes: [
          GoRoute(
            path: '/learner',
            pageBuilder: (ctx, state) => _fade(state, const LearnerDashboardScreen()),
          ),
          GoRoute(
            path: '/learner/catalog',
            pageBuilder: (ctx, state) => _fade(state, const CourseCatalogScreen()),
          ),
          GoRoute(
            path: '/learner/my-courses',
            pageBuilder: (ctx, state) => _fade(state, const MyCoursesScreen()),
          ),
          GoRoute(
            path: '/learner/assessments',
            pageBuilder: (ctx, state) => _fade(state, const AssessmentsScreen()),
          ),
          GoRoute(
            path: '/learner/course/:id',
            pageBuilder: (ctx, state) => _fade(
              state,
              CourseDetailScreen(id: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/learner/lesson/:courseId/:lessonId',
            pageBuilder: (ctx, state) => _fade(
              state,
              LessonPlayerScreen(
                courseId: state.pathParameters['courseId']!,
                lessonId: state.pathParameters['lessonId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/learner/assessment/:courseId',
            pageBuilder: (ctx, state) => _fade(
              state,
              AssessmentIntroScreen(courseId: state.pathParameters['courseId']!),
            ),
          ),
          GoRoute(
            path: '/learner/assessment/:courseId/quiz',
            pageBuilder: (ctx, state) => _fade(
              state,
              AssessmentQuizScreen(courseId: state.pathParameters['courseId']!),
            ),
          ),
          GoRoute(
            path: '/learner/assessment/:courseId/result',
            pageBuilder: (ctx, state) => _fade(
              state,
              AssessmentResultScreen(courseId: state.pathParameters['courseId']!),
            ),
          ),
          GoRoute(
            path: '/learner/assessment/:courseId/review',
            pageBuilder: (ctx, state) => _fade(
              state,
              AssessmentReviewScreen(courseId: state.pathParameters['courseId']!),
            ),
          ),
          GoRoute(
            path: '/learner/assessment/:courseId/flashcards',
            pageBuilder: (ctx, state) => _fade(
              state,
              AssessmentFlashcardsScreen(courseId: state.pathParameters['courseId']!),
            ),
          ),
          GoRoute(
            path: '/learner/certificates',
            pageBuilder: (ctx, state) => _fade(state, const CertificatesScreen()),
          ),
          GoRoute(
            path: '/learner/support',
            pageBuilder: (ctx, state) => _fade(state, const SupportScreen()),
          ),
          GoRoute(
            path: '/learner/profile',
            pageBuilder: (ctx, state) => _fade(state, const ProfileScreen()),
          ),
          GoRoute(
            path: '/learner/resources',
            pageBuilder: (ctx, state) => _fade(state, const ResourcesScreen()),
          ),
          GoRoute(
            path: '/learner/ai',
            pageBuilder: (ctx, state) => _fade(state, const ArrestoAiScreen()),
          ),
        ],
      ),
      ShellRoute(
        builder: (ctx, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin',
            pageBuilder: (ctx, state) => _fade(state, const AdminDashboardScreen()),
          ),
          GoRoute(
            path: '/admin/generator',
            pageBuilder: (ctx, state) => _fade(state, const CourseGeneratorWizard()),
          ),
          GoRoute(
            path: '/admin/learners',
            pageBuilder: (ctx, state) => _fade(state, const LearnersScreen()),
          ),
          GoRoute(
            path: '/admin/learners/:id',
            pageBuilder: (ctx, state) => _fade(
              state,
              LearnerDetailScreen(id: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/admin/analytics',
            pageBuilder: (ctx, state) => _fade(state, const AnalyticsScreen()),
          ),
          GoRoute(
            path: '/admin/support',
            pageBuilder: (ctx, state) => _fade(state, const AdminSupportScreen()),
          ),
          GoRoute(
            path: '/admin/support/:ticketId',
            pageBuilder: (ctx, state) => _fade(
              state,
              TicketDetailScreen(id: state.pathParameters['ticketId']!),
            ),
          ),
          GoRoute(
            path: '/admin/courses',
            pageBuilder: (ctx, state) => _fade(state, const AllCoursesScreen()),
          ),
          GoRoute(
            path: '/admin/settings',
            pageBuilder: (ctx, state) => _fade(state, const SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage<void> _fade<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(CurveTween(curve: Curves.easeOut).animate(animation)),
          child: child,
        ),
      );
    },
  );
}
