import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../data/providers/api_providers.dart';

class AssessmentResultScreen extends ConsumerWidget {
  final String courseId;
  const AssessmentResultScreen({super.key, required this.courseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizResult = ref.watch(quizResultsProvider);

    final correct = quizResult?.correct ?? 0;
    final total = quizResult?.total ?? 0;
    final score = quizResult?.score ?? 0;
    final passPct = quizResult?.passPct ?? 70;
    final passed = score >= passPct;
    final elapsed = quizResult?.elapsedSeconds ?? 0;
    final elapsedStr = _formatTime(elapsed);

    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Pass/Fail hero
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: passed ? ArrestoColors.greenSoft : ArrestoColors.redSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: passed ? ArrestoColors.green : ArrestoColors.red),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color:
                          passed ? ArrestoColors.green : ArrestoColors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      passed ? Icons.check_rounded : Icons.close_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    passed ? 'Assessment Passed!' : 'Assessment Failed',
                    style: ArrestoText.h2(
                        color: passed
                            ? ArrestoColors.green
                            : ArrestoColors.red),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    passed
                        ? 'Congratulations! You\'ve passed the assessment.'
                        : 'You scored below the $passPct% pass mark. Please retake.',
                    style: ArrestoText.body(),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Score metrics
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.4,
              children: [
                _metric('Score', '$score%',
                    passed ? ArrestoColors.green : ArrestoColors.red),
                _metric('Correct', '$correct', ArrestoColors.green),
                _metric('Incorrect', '${total - correct}', ArrestoColors.red),
                _metric('Time', elapsedStr, ArrestoColors.blue),
              ],
            ),
            const SizedBox(height: 20),

            // Question breakdown (real data from quiz results)
            if (quizResult != null && quizResult.questions.isNotEmpty)
              ArrestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Question Breakdown', style: ArrestoText.h4()),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        quizResult.questions.length,
                        (i) {
                          final q = quizResult.questions[i];
                          final selectedKey = quizResult.answers[q.id];
                          final wasCorrect = selectedKey != null &&
                              selectedKey == quizResult.correctAnswers[q.id];
                          final skipped = selectedKey == null;

                          Color bg;
                          Color border;
                          IconData icon;
                          Color iconColor;

                          if (skipped) {
                            bg = ArrestoColors.bg2;
                            border = ArrestoColors.line;
                            icon = Icons.remove_rounded;
                            iconColor = ArrestoColors.textMuted;
                          } else if (wasCorrect) {
                            bg = ArrestoColors.greenSoft;
                            border = ArrestoColors.green;
                            icon = Icons.check_rounded;
                            iconColor = ArrestoColors.green;
                          } else {
                            bg = ArrestoColors.redSoft;
                            border = ArrestoColors.red;
                            icon = Icons.close_rounded;
                            iconColor = ArrestoColors.red;
                          }

                          return Tooltip(
                            message: skipped
                                ? 'Q${i + 1}: Skipped'
                                : 'Q${i + 1}: ${wasCorrect ? 'Correct' : 'Incorrect'}',
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: border),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icon, size: 14, color: iconColor),
                                  Text(
                                    'Q${i + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: iconColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      _legend(ArrestoColors.greenSoft, ArrestoColors.green,
                          Icons.check_rounded, 'Correct'),
                      const SizedBox(width: 16),
                      _legend(ArrestoColors.redSoft, ArrestoColors.red,
                          Icons.close_rounded, 'Incorrect'),
                      const SizedBox(width: 16),
                      _legend(ArrestoColors.bg2, ArrestoColors.textMuted,
                          Icons.remove_rounded, 'Skipped'),
                    ]),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Actions
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ArrestoButton(
                  label: 'Review Answers',
                  variant: ArrestoButtonVariant.ghost,
                  icon: const Icon(Icons.list_alt_rounded),
                  onPressed: () => context
                      .go('/learner/assessment/$courseId/review'),
                ),
                if (!passed)
                  ArrestoButton(
                    label: 'Retake Assessment',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => context
                        .go('/learner/assessment/$courseId'),
                  ),
                if (passed)
                  ArrestoButton(
                    label: 'Download Certificate',
                    icon: const Icon(Icons.workspace_premium_rounded),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Certificate download coming soon — check the Certificates tab.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ArrestoButton(
                  label: 'Back to Course',
                  variant: ArrestoButtonVariant.dark,
                  onPressed: () =>
                      context.go('/learner/course/$courseId'),
                ),
              ],
            ),
          ],
        ),
      );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _metric(String label, String value, Color color) {
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
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label, style: ArrestoText.xs()),
        ],
      ),
    );
  }

  Widget _legend(Color bg, Color fg, IconData icon, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: fg),
        ),
        child: Icon(icon, size: 12, color: fg),
      ),
      const SizedBox(width: 4),
      Text(label, style: ArrestoText.xs()),
    ]);
  }
}
