import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/api/models.dart';
import '../../../core/api/progress_service.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/progress_bar.dart';

// Fetches aggregate progress for all courses for a given learnerId.
final _progressProvider = FutureProvider.family<_AggProgress, String>((ref, learnerId) async {
  final lib = await ref.watch(libraryProvider.future);
  int completedLessons = 0;
  int totalAttempts = 0;
  double scoreSum = 0;
  int scoredCourses = 0;
  final List<_CourseProgress> courses = [];

  for (final item in lib) {
    try {
      final p = await ProgressService.getCourseProgress(learnerId, item.sourceFile);
      final completed = (p['completed_lessons'] as num?)?.toInt() ?? 0;
      final avg = (p['average_checkpoint_score'] as num?)?.toDouble() ?? 0;
      final records = (p['lesson_records'] as List? ?? []);
      final attempts = records.where((r) => (r as Map)['checkpoint_score'] != null).length;

      completedLessons += completed;
      totalAttempts += attempts;
      if (avg > 0) { scoreSum += avg; scoredCourses++; }
      if (completed > 0) {
        courses.add(_CourseProgress(
          item: item,
          completed: completed,
          avgScore: avg,
        ));
      }
    } catch (_) {
      // course not started — skip
    }
  }

  return _AggProgress(
    completedLessons: completedLessons,
    totalAttempts: totalAttempts,
    avgScore: scoredCourses > 0 ? (scoreSum / scoredCourses * 100).round() : 0,
    activeCourses: courses,
  );
});

class _AggProgress {
  final int completedLessons, totalAttempts, avgScore;
  final List<_CourseProgress> activeCourses;
  const _AggProgress({
    required this.completedLessons, required this.totalAttempts,
    required this.avgScore, required this.activeCourses,
  });
}

class _CourseProgress {
  final LibraryItem item;
  final int completed;
  final double avgScore;
  const _CourseProgress({required this.item, required this.completed, required this.avgScore});
}

// ─────────────────────────────────────────────────────────────────

class LearnerDashboardScreen extends ConsumerWidget {
  const LearnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final learnerId = auth.user?.email ?? 'learner';
    final libAsync = ref.watch(libraryProvider);
    final progressAsync = ref.watch(_progressProvider(learnerId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Greeting
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome back, ${auth.user?.name.split(' ').first ?? 'Learner'}!',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
            const Text('Pick up where you left off',
                style: TextStyle(fontSize: 14, color: AColors.textMuted)),
          ])),
          AButton(
            label: 'Browse Catalog',
            icon: Icons.explore_rounded,
            variant: AButtonVariant.ghost,
            onPressed: () => context.go('/learner/catalog'),
          ),
        ]),
        const SizedBox(height: 28),

        // Stats from real progress API
        progressAsync.when(
          loading: () => GridView.count(
            crossAxisCount: 4, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.4,
            children: const [
              StatCard(label: 'In Progress', value: '…', icon: Icons.library_books_rounded, barColor: AColors.amber),
              StatCard(label: 'Lessons Done', value: '…', icon: Icons.check_rounded, barColor: AColors.green),
              StatCard(label: 'Quiz Attempts', value: '…', icon: Icons.quiz_outlined, barColor: AColors.blue),
              StatCard(label: 'Avg Score', value: '…', icon: Icons.bar_chart_rounded, barColor: AColors.orange),
            ],
          ),
          error: (_, __) => GridView.count(
            crossAxisCount: 4, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.4,
            children: const [
              StatCard(label: 'In Progress', value: '0', icon: Icons.library_books_rounded, barColor: AColors.amber),
              StatCard(label: 'Lessons Done', value: '0', icon: Icons.check_rounded, barColor: AColors.green),
              StatCard(label: 'Quiz Attempts', value: '0', icon: Icons.quiz_outlined, barColor: AColors.blue),
              StatCard(label: 'Avg Score', value: '—', icon: Icons.bar_chart_rounded, barColor: AColors.orange),
            ],
          ),
          data: (p) => GridView.count(
            crossAxisCount: 4, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.4,
            children: [
              StatCard(label: 'In Progress', value: '${p.activeCourses.length}',
                  icon: Icons.library_books_rounded, barColor: AColors.amber),
              StatCard(label: 'Lessons Done', value: '${p.completedLessons}',
                  icon: Icons.check_rounded, barColor: AColors.green),
              StatCard(label: 'Quiz Attempts', value: '${p.totalAttempts}',
                  icon: Icons.quiz_outlined, barColor: AColors.blue),
              StatCard(label: 'Avg Score', value: p.avgScore > 0 ? '${p.avgScore}%' : '—',
                  icon: Icons.bar_chart_rounded, barColor: AColors.orange),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // In-progress courses (from progress API)
        progressAsync.maybeWhen(
          data: (p) => p.activeCourses.isNotEmpty ? Column(children: [
            APanel(
              title: 'Continue Learning',
              subtitle: '${p.activeCourses.length} course${p.activeCourses.length == 1 ? '' : 's'} in progress',
              child: Column(children: p.activeCourses.map((cp) => _InProgressTile(cp)).toList()),
            ),
            const SizedBox(height: 24),
          ]) : const SizedBox(),
          orElse: () => const SizedBox(),
        ),

        // All available courses
        APanel(
          title: 'Available Courses',
          subtitle: 'Browse our full catalog',
          action: TextButton(
            onPressed: () => context.go('/learner/catalog'),
            child: const Text('View all', style: TextStyle(fontSize: 13, color: AColors.blue)),
          ),
          child: libAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (items) => items.isEmpty
                ? const Text('No courses available yet.', style: TextStyle(color: AColors.textMuted))
                : Column(children: items.take(5).map((item) => _CourseTile(item)).toList()),
          ),
        ),
        const SizedBox(height: 24),

        // AI Tutor CTA
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AColors.ink, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
              child: const Center(child: Text('AI', style: TextStyle(fontWeight: FontWeight.w800, color: AColors.ink))),
            ),
            const SizedBox(width: 16),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Arresto AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('Ask anything about safety training or your courses',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ])),
            AButton(
              label: 'Ask Arresto AI',
              variant: AButtonVariant.primary,
              size: AButtonSize.sm,
              onPressed: () {},
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InProgressTile extends StatelessWidget {
  const _InProgressTile(this.cp);
  final _CourseProgress cp;

  @override
  Widget build(BuildContext context) {
    final pct = cp.item.totalLessons > 0
        ? (cp.completed / cp.item.totalLessons).clamp(0.0, 1.0)
        : 0.0;
    return InkWell(
      onTap: () => context.go('/learner/catalog/${cp.item.scriptId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AColors.amberSoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.play_circle_outline_rounded, color: AColors.orange, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cp.item.courseTitle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AColors.ink),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            AProgressBarLabeled(
              value: pct,
              label: '${cp.completed}/${cp.item.totalLessons} lessons',
            ),
          ])),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right_rounded, color: AColors.textMuted),
        ]),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile(this.item);
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/learner/catalog/${item.scriptId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AColors.amberSoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.school_rounded, color: AColors.orange, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.courseTitle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AColors.ink),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${item.totalLessons} lessons · ${item.estimatedDurationMin}m',
                style: const TextStyle(fontSize: 12, color: AColors.textMuted)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AColors.textMuted),
        ]),
      ),
    );
  }
}
