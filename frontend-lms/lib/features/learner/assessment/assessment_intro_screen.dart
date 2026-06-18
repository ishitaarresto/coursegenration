import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/providers/api_providers.dart';

class AssessmentIntroScreen extends ConsumerWidget {
  final String courseId;
  const AssessmentIntroScreen({super.key, required this.courseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(courseDetailProvider(courseId));
    final attemptsAsync = ref.watch(assessmentAttemptsProvider(courseId));
    final detail = detailAsync.valueOrNull;

    final courseTitle = detail?['course_script']?['course_title'] as String? ??
        'Course Assessment';
    final numQuestions =
        (detail?['assessment_num_questions'] as num?)?.toInt() ?? 5;
    final passPct =
        (detail?['assessment_pass_pct'] as num?)?.toInt() ?? 70;
    final timeMin =
        (detail?['assessment_time_min'] as num?)?.toInt() ?? 30;
    final maxRetakes =
        (detail?['assessment_retakes'] as num?)?.toInt() ?? 3;

    final attempts = attemptsAsync.valueOrNull ?? [];
    final attemptsLeft =
        maxRetakes == 0 ? '∞' : '${(maxRetakes - attempts.length).clamp(0, maxRetakes)}';

    return Column(
      children: [
        AppBar(
          backgroundColor: ArrestoColors.surface,
          foregroundColor: ArrestoColors.ink,
          title: const Text('Assessment'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  icon: Icons.assignment_rounded,
                  title: courseTitle,
                  subtitle: 'AI-generated questions based on course content',
                ),
                const SizedBox(height: 20),

                // Stats grid
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _infoCard(Icons.quiz_rounded, '$numQuestions',
                        'Questions', ArrestoColors.blue),
                    _infoCard(Icons.check_circle_rounded, '$passPct%',
                        'Pass Mark', ArrestoColors.green),
                    _infoCard(Icons.schedule_rounded, '$timeMin min',
                        'Time Limit', ArrestoColors.orange),
                    _infoCard(Icons.refresh_rounded, attemptsLeft,
                        'Attempts Left', ArrestoColors.amber),
                  ],
                ),
                const SizedBox(height: 24),

                // Previous attempts
                ArrestoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Previous Attempts', style: ArrestoText.h4()),
                      const SizedBox(height: 12),
                      if (attemptsAsync.isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                                color: ArrestoColors.orange),
                          ),
                        )
                      else if (attempts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No attempts yet.',
                              style: ArrestoText.body(
                                  color: ArrestoColors.textMuted)),
                        )
                      else
                        ...attempts.asMap().entries.map((entry) {
                          final i = entry.key;
                          final a = entry.value;
                          return _attemptRow(
                            'Attempt ${attempts.length - i}',
                            '${a.score}%',
                            a.passed ? 'Passed' : 'Failed',
                            a.formattedDate,
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                ArrestoButton(
                  label: 'Study Flashcards',
                  fullWidth: true,
                  size: ArrestoButtonSize.lg,
                  variant: ArrestoButtonVariant.ghost,
                  icon: const Icon(Icons.style_rounded),
                  onPressed: () =>
                      context.go('/learner/assessment/$courseId/flashcards'),
                ),
                const SizedBox(height: 10),
                ArrestoButton(
                  label: 'Start Assessment',
                  fullWidth: true,
                  size: ArrestoButtonSize.lg,
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () =>
                      context.go('/learner/assessment/$courseId/quiz'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, String value, String label, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: ArrestoText.h3(color: color)),
          Text(label, style: ArrestoText.xs()),
        ],
      ),
    );
  }

  Widget _attemptRow(
      String attempt, String score, String status, String date) {
    final passed = status == 'Passed';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: passed ? ArrestoColors.greenSoft : ArrestoColors.redSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              score,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: passed ? ArrestoColors.green : ArrestoColors.red,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attempt, style: ArrestoText.bodyBold()),
                Text(date, style: ArrestoText.xs()),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color:
                  passed ? ArrestoColors.greenSoft : ArrestoColors.redSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color:
                    passed ? ArrestoColors.green : ArrestoColors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
