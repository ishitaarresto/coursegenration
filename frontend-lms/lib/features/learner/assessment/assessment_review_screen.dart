import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../data/providers/api_providers.dart';

class AssessmentReviewScreen extends ConsumerWidget {
  final String courseId;
  const AssessmentReviewScreen({super.key, required this.courseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizResult = ref.watch(quizResultsProvider);

    return Column(
      children: [
        AppBar(
          backgroundColor: ArrestoColors.surface,
          foregroundColor: ArrestoColors.ink,
          title: Text('Review Answers', style: ArrestoText.h4()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        if (quizResult == null || quizResult.questions.isEmpty)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.assignment_outlined,
                    color: ArrestoColors.textMuted2, size: 48),
                const SizedBox(height: 12),
                Text('No review available.', style: ArrestoText.body()),
                const SizedBox(height: 4),
                Text('Complete an assessment first.', style: ArrestoText.small()),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => context.go('/learner/assessment/$courseId'),
                  child: const Text('Go to Assessment'),
                ),
              ]),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: quizResult.questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (ctx, i) {
                final q = quizResult.questions[i];
                final selectedKey = quizResult.answers[q.id];
                final correctKey =
                    quizResult.correctAnswers[q.id] ?? q.correctAnswer;
                final explanation =
                    quizResult.explanations[q.id] ?? q.explanation;
                final wasCorrect =
                    selectedKey != null && selectedKey == correctKey;
                final skipped = selectedKey == null;

                return ArrestoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: skipped
                                  ? ArrestoColors.bg2
                                  : wasCorrect
                                      ? ArrestoColors.greenSoft
                                      : ArrestoColors.redSoft,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              skipped
                                  ? Icons.remove_rounded
                                  : wasCorrect
                                      ? Icons.check_rounded
                                      : Icons.close_rounded,
                              size: 16,
                              color: skipped
                                  ? ArrestoColors.textMuted
                                  : wasCorrect
                                      ? ArrestoColors.green
                                      : ArrestoColors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Q${i + 1}', style: ArrestoText.label()),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: skipped
                                  ? ArrestoColors.bg2
                                  : wasCorrect
                                      ? ArrestoColors.greenSoft
                                      : ArrestoColors.redSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              skipped
                                  ? 'Skipped'
                                  : wasCorrect
                                      ? 'Correct'
                                      : 'Incorrect',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: skipped
                                    ? ArrestoColors.textMuted
                                    : wasCorrect
                                        ? ArrestoColors.green
                                        : ArrestoColors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Question text
                      Text(q.question, style: ArrestoText.bodyBold()),
                      const SizedBox(height: 10),

                      // Options
                      ...q.options.entries.map((opt) {
                        final isSelected = selectedKey == opt.key;
                        final isCorrectOpt = opt.key == correctKey;

                        Color bg = ArrestoColors.surface;
                        Color border = ArrestoColors.line;

                        if (isCorrectOpt) {
                          bg = ArrestoColors.greenSoft;
                          border = ArrestoColors.green;
                        } else if (isSelected && !isCorrectOpt) {
                          bg = ArrestoColors.redSoft;
                          border = ArrestoColors.red;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            children: [
                              Text(
                                opt.key,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isCorrectOpt
                                        ? ArrestoColors.green
                                        : ArrestoColors.textMuted),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(opt.value,
                                    style: ArrestoText.body(
                                        color: isCorrectOpt
                                            ? ArrestoColors.green
                                            : null)),
                              ),
                              if (isCorrectOpt)
                                const Icon(Icons.check_circle_rounded,
                                    size: 16, color: ArrestoColors.green),
                              if (isSelected && !isCorrectOpt)
                                const Icon(Icons.cancel_rounded,
                                    size: 16, color: ArrestoColors.red),
                            ],
                          ),
                        );
                      }),

                      // Explanation
                      if (explanation.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ArrestoColors.surfaceSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ArrestoColors.line),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lightbulb_rounded,
                                  size: 14, color: ArrestoColors.amber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(explanation,
                                    style: ArrestoText.bodySm()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
