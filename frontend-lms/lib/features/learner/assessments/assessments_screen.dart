import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/services/assessment_service.dart';
import '../../../data/models/course.dart';
import '../../../data/providers/api_providers.dart';

class AssessmentsScreen extends ConsumerWidget {
  const AssessmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(libraryProvider);
    final historyAsync = ref.watch(assessmentHistoryProvider);

    return RefreshIndicator(
      color: ArrestoColors.orange,
      onRefresh: () async {
        ref.invalidate(libraryProvider);
        ref.invalidate(assessmentHistoryProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.assignment_rounded,
              title: 'Assessments',
              subtitle: 'Your quizzes, scores and certification status',
            ),
            const SizedBox(height: 24),

            // ── Available to take ──────────────────────────────────────────
            Row(children: [
              const Icon(Icons.list_alt_rounded,
                  size: 18, color: ArrestoColors.orange),
              const SizedBox(width: 8),
              Text('Available to take', style: ArrestoText.h3()),
            ]),
            const SizedBox(height: 14),
            coursesAsync.when(
              loading: () => const _LoadingCards(),
              error: (e, _) => _ErrorBanner(
                message: 'Could not load courses: $e',
                onRetry: () => ref.invalidate(libraryProvider),
              ),
              data: (courses) {
                if (courses.isEmpty) {
                  return _EmptyState(
                    icon: Icons.list_alt_rounded,
                    message: 'No courses in the library yet.',
                    sub: 'Ask your admin to publish a course.',
                  );
                }
                return LayoutBuilder(builder: (ctx, c) {
                  final cols = c.maxWidth > 640 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: courses.length,
                    itemBuilder: (ctx, i) =>
                        _AvailableCard(course: courses[i]),
                  );
                });
              },
            ),
            const SizedBox(height: 28),

            // ── Results & history ──────────────────────────────────────────
            Row(children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 18, color: ArrestoColors.orange),
              const SizedBox(width: 8),
              Text('Results & history', style: ArrestoText.h3()),
            ]),
            const SizedBox(height: 14),
            historyAsync.when(
              loading: () => const _HistoryShimmer(),
              error: (e, _) => _ErrorBanner(
                message: 'Could not load history: $e',
                onRetry: () => ref.invalidate(assessmentHistoryProvider),
              ),
              data: (history) {
                if (history.isEmpty) {
                  return _EmptyState(
                    icon: Icons.bar_chart_rounded,
                    message: 'No assessments taken yet.',
                    sub: 'Take an assessment above to see your results here.',
                  );
                }
                return ArrestoCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: history
                        .map((h) => _HistoryRow(item: h))
                        .toList(),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Available card ─────────────────────────────────────────────────────────────

class _AvailableCard extends StatelessWidget {
  final Course course;
  const _AvailableCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      child: Row(children: [
        Container(
          width:  44,
          height: 44,
          decoration: BoxDecoration(
            color:        ArrestoColors.orangeTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.list_alt_rounded,
              color: ArrestoColors.orange, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(course.title,
                  style:    ArrestoText.bodyBold(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                '${course.lessons > 0 ? '${course.lessons} lessons · ' : ''}AI-generated questions',
                style: ArrestoText.small(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ArrestoButton(
          label:     'Take assessment',
          size:      ArrestoButtonSize.sm,
          onPressed: () => context.go('/learner/assessment/${course.id}'),
        ),
      ]),
    );
  }
}

// ── History row ────────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final AssessmentHistoryItem item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final passed = item.passed;
    final bg     = passed ? ArrestoColors.greenSoft : ArrestoColors.redSoft;
    final fg     = passed ? ArrestoColors.green     : ArrestoColors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: ArrestoColors.line, width: 0.5)),
      ),
      child: Row(children: [
        // Score circle
        Container(
          width:     52,
          height:    52,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            '${item.score}',
            style: TextStyle(
              fontSize:   18,
              fontWeight: FontWeight.w800,
              color:      fg,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.courseTitle,
                  style:    ArrestoText.bodyBold(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(item.attemptLabel, style: ArrestoText.xs()),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ArrestoBadge(
          label:   passed ? 'Passed' : 'Failed',
          variant: passed ? BadgeVariant.green : BadgeVariant.red,
          dot:     true,
        ),
        const SizedBox(width: 10),
        ArrestoButton(
          label:    'Review',
          size:     ArrestoButtonSize.sm,
          variant:  ArrestoButtonVariant.ghost,
          icon:     const Icon(Icons.visibility_rounded),
          onPressed: () =>
              context.go('/learner/assessment/${item.courseId}/review'),
        ),
        if (!passed) ...[
          const SizedBox(width: 6),
          ArrestoButton(
            label:     'Retake',
            size:      ArrestoButtonSize.sm,
            icon:      const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.go('/learner/assessment/${item.courseId}'),
          ),
        ],
      ]),
    );
  }
}

// ── Loading skeletons ──────────────────────────────────────────────────────────

class _LoadingCards extends StatelessWidget {
  const _LoadingCards();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(2, (_) => Container(
        height:  80,
        margin:  const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        ArrestoColors.bg2,
          borderRadius: BorderRadius.circular(12),
        ),
      )),
    );
  }
}

class _HistoryShimmer extends StatelessWidget {
  const _HistoryShimmer();

  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: List.generate(3, (i) => Container(
          height:     72,
          margin:     const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color:        ArrestoColors.bg2,
            borderRadius: BorderRadius.circular(8),
          ),
        )),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  const _EmptyState(
      {required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color:        ArrestoColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: ArrestoColors.line),
      ),
      child: Column(children: [
        Icon(icon, size: 36, color: ArrestoColors.textMuted2),
        const SizedBox(height: 10),
        Text(message,
            style:     ArrestoText.bodyBold(color: ArrestoColors.textMuted),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(sub,
            style:     ArrestoText.small(),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        ArrestoColors.redSoft,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: ArrestoColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded,
            color: ArrestoColors.red, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: ArrestoText.small(color: ArrestoColors.red))),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: ArrestoColors.red),
          child: const Text('Retry'),
        ),
      ]),
    );
  }
}
