import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/api/progress_service.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/arresto_badge.dart';

class _AssessmentRecord {
  final String courseTitle;
  final int moduleIdx;
  final int lessonIdx;
  final double score;
  final bool passed;
  _AssessmentRecord({
    required this.courseTitle,
    required this.moduleIdx,
    required this.lessonIdx,
    required this.score,
  }) : passed = score >= 0.7;

  String get lessonLabel => 'Module $moduleIdx, Lesson $lessonIdx';
}

class _AssessmentSummary {
  final int attempts;
  final int passed;
  final double avgScore;
  final List<_AssessmentRecord> records;
  const _AssessmentSummary({required this.attempts, required this.passed, required this.avgScore, required this.records});
}

final _assessmentsProvider = FutureProvider.family<_AssessmentSummary, String>((ref, learnerId) async {
  final lib = await ref.watch(libraryProvider.future);
  final allRecords = <_AssessmentRecord>[];

  for (final item in lib) {
    try {
      final p = await ProgressService.getCourseProgress(learnerId, item.sourceFile);
      final records = (p['lesson_records'] as List? ?? []);
      for (final r in records) {
        final rec = r as Map<String, dynamic>;
        final score = (rec['checkpoint_score'] as num?)?.toDouble();
        if (score != null) {
          allRecords.add(_AssessmentRecord(
            courseTitle: item.courseTitle,
            moduleIdx: (rec['module_idx'] as num?)?.toInt() ?? 1,
            lessonIdx: (rec['lesson_idx'] as num?)?.toInt() ?? 1,
            score: score,
          ));
        }
      }
    } catch (_) {}
  }

  final passed = allRecords.where((r) => r.passed).length;
  final avgScore = allRecords.isEmpty ? 0.0
      : allRecords.fold(0.0, (s, r) => s + r.score) / allRecords.length;

  return _AssessmentSummary(
    attempts: allRecords.length,
    passed: passed,
    avgScore: avgScore,
    records: allRecords,
  );
});

class AssessmentsScreen extends ConsumerWidget {
  const AssessmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final learnerId = auth.user?.email ?? 'learner';
    final summaryAsync = ref.watch(_assessmentsProvider(learnerId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Assessments', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Track your quiz and checkpoint results', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 28),

        summaryAsync.when(
          loading: () => GridView.count(
            crossAxisCount: 3, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.6,
            children: const [
              StatCard(label: 'Total Attempts', value: '…', icon: Icons.quiz_outlined, barColor: AColors.amber),
              StatCard(label: 'Passed', value: '…', icon: Icons.check_circle_outline, barColor: AColors.green),
              StatCard(label: 'Average Score', value: '…', icon: Icons.bar_chart_rounded, barColor: AColors.blue),
            ],
          ),
          error: (_, __) => GridView.count(
            crossAxisCount: 3, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.6,
            children: const [
              StatCard(label: 'Total Attempts', value: '0', icon: Icons.quiz_outlined, barColor: AColors.amber),
              StatCard(label: 'Passed', value: '0', icon: Icons.check_circle_outline, barColor: AColors.green),
              StatCard(label: 'Average Score', value: '—', icon: Icons.bar_chart_rounded, barColor: AColors.blue),
            ],
          ),
          data: (s) => GridView.count(
            crossAxisCount: 3, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.6,
            children: [
              StatCard(label: 'Total Attempts', value: '${s.attempts}',
                  icon: Icons.quiz_outlined, barColor: AColors.amber),
              StatCard(label: 'Passed', value: '${s.passed}',
                  icon: Icons.check_circle_outline, barColor: AColors.green),
              StatCard(label: 'Average Score',
                  value: s.attempts > 0 ? '${(s.avgScore * 100).round()}%' : '—',
                  icon: Icons.bar_chart_rounded, barColor: AColors.blue),
            ],
          ),
        ),
        const SizedBox(height: 28),

        APanel(
          title: 'Assessment History',
          child: summaryAsync.when(
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => _EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load assessments',
              subtitle: e.toString(),
            ),
            data: (s) => s.records.isEmpty
                ? const _EmptyState(
                    icon: Icons.quiz_outlined,
                    title: 'No checkpoints completed yet',
                    subtitle: 'Complete lessons and pass checkpoints to see results here.',
                  )
                : Column(children: [
                    // Header row
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: const [
                        Expanded(flex: 3, child: Text('Course', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.textMuted))),
                        Expanded(flex: 2, child: Text('Lesson', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.textMuted))),
                        SizedBox(width: 80, child: Text('Score', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.textMuted), textAlign: TextAlign.center)),
                        SizedBox(width: 80, child: Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.textMuted), textAlign: TextAlign.center)),
                      ]),
                    ),
                    const Divider(height: 1),
                    ...s.records.map((r) => _RecordRow(r)),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow(this.r);
  final _AssessmentRecord r;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(flex: 3, child: Text(r.courseTitle,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Text(r.lessonLabel,
            style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
        SizedBox(width: 80, child: Text('${(r.score * 100).round()}%',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: r.passed ? AColors.green : AColors.red,
            ), textAlign: TextAlign.center)),
        SizedBox(width: 80, child: Center(child: ABadge(
          r.passed ? 'Passed' : 'Failed',
          variant: r.passed ? ABadgeVariant.green : ABadgeVariant.red,
        ))),
      ]),
    );
  }

}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: AColors.textMuted2),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AColors.ink)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: AColors.textMuted), textAlign: TextAlign.center),
      ]),
    ),
  );
}
