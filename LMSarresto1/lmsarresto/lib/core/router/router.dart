import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/admin/dashboard/admin_dashboard_screen.dart';
import '../../features/admin/generator/generator_screen.dart';
import '../../features/admin/courses/courses_screen.dart';
import '../../features/admin/courses/course_detail_screen.dart';
import '../../features/admin/courses/script_editor_screen.dart';
import '../../features/admin/learners/learners_screen.dart';
import '../../features/admin/analytics/analytics_screen.dart';
import '../../features/admin/support/admin_support_screen.dart';
import '../../features/admin/settings/settings_screen.dart';
import '../../features/admin/studio/author_studio_screen.dart';
import '../../features/learner/dashboard/learner_dashboard_screen.dart';
import '../../features/learner/catalog/catalog_screen.dart';
import '../../features/learner/catalog/course_detail_screen.dart';
import '../../features/learner/lesson_player/lesson_player_screen.dart';
import '../../features/learner/lesson_player/item_player_screen.dart';
import '../../features/learner/assessments/assessments_screen.dart';
import '../../features/learner/certificates/certificates_screen.dart';
import '../../features/learner/support/learner_support_screen.dart';
import '../../shared/widgets/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) {
        return auth.isAdmin ? '/admin' : '/learner';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

      // ── Admin shell ──────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(role: 'admin', child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
          GoRoute(path: '/admin/generator', builder: (_, __) => const GeneratorScreen()),
          GoRoute(path: '/admin/courses', builder: (_, __) => const CoursesScreen()),
          GoRoute(
              path: '/admin/courses/:id',
              builder: (_, s) => AdminCourseDetailScreen(scriptId: s.pathParameters['id']!)),
          GoRoute(
              path: '/admin/courses/:id/script',
              builder: (_, s) => ScriptEditorScreen(scriptId: s.pathParameters['id']!)),
          GoRoute(path: '/admin/learners', builder: (_, __) => const LearnersScreen()),
          GoRoute(path: '/admin/analytics', builder: (_, __) => const AnalyticsScreen()),
          GoRoute(path: '/admin/support', builder: (_, __) => const AdminSupportScreen()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/admin/studio', builder: (_, __) => const AuthorStudioScreen()),
        ],
      ),

      // ── Learner shell ────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(role: 'learner', child: child),
        routes: [
          GoRoute(path: '/learner', builder: (_, __) => const LearnerDashboardScreen()),
          GoRoute(path: '/learner/catalog', builder: (_, __) => const CatalogScreen()),
          GoRoute(
              path: '/learner/catalog/:id',
              builder: (_, s) => LearnerCourseDetailScreen(scriptId: s.pathParameters['id']!)),
          GoRoute(
              path: '/learner/lesson/:courseId/:lessonRef',
              builder: (_, s) => LessonPlayerScreen(
                    scriptId: s.pathParameters['courseId']!,
                    lessonRef: s.pathParameters['lessonRef']!,
                  )),
          GoRoute(
              path: '/learner/play/:courseId/:itemIndex',
              builder: (_, s) => ItemPlayerScreen(
                    scriptId: s.pathParameters['courseId']!,
                    startIndex: int.tryParse(s.pathParameters['itemIndex']!) ?? 0,
                  )),
          GoRoute(path: '/learner/assessments', builder: (_, __) => const AssessmentsScreen()),
          GoRoute(path: '/learner/certificates', builder: (_, __) => const CertificatesScreen()),
          GoRoute(path: '/learner/support', builder: (_, __) => const LearnerSupportScreen()),
        ],
      ),
    ],
  );
});
