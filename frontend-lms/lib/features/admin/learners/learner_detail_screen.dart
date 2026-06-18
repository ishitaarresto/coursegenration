import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../data/providers/api_providers.dart';

class LearnerDetailScreen extends ConsumerWidget {
  final String id;
  const LearnerDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learnerAsync = ref.watch(learnerDetailApiProvider(id));
    final learner = learnerAsync.valueOrNull;
    if (learner == null) {
      return Scaffold(
        backgroundColor: ArrestoColors.background,
        appBar: AppBar(
          backgroundColor: ArrestoColors.surface,
          foregroundColor: ArrestoColors.ink,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: learnerAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Learner not found.')),
      );
    }


    return Scaffold(
      backgroundColor: ArrestoColors.background,
      appBar: AppBar(
        backgroundColor: ArrestoColors.surface,
        foregroundColor: ArrestoColors.ink,
        title: Text(learner.name, style: ArrestoText.h4()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ArrestoCard(
              child: Row(
                children: [
                  ArrestoAvatar(name: learner.name, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(learner.name, style: ArrestoText.h3()),
                        Text(learner.email, style: ArrestoText.small()),
                        const SizedBox(height: 6),
                        StatusBadge(status: learner.status),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Last active', style: ArrestoText.xs()),
                      Text(learner.lastActive,
                          style: ArrestoText.small(color: ArrestoColors.ink)
                              .copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('${learner.enrolled}', 'Enrolled'),
                const SizedBox(width: 12),
                _stat('${learner.progress}%', 'Progress'),
                const SizedBox(width: 12),
                _stat(learner.time, 'Time Spent'),
                const SizedBox(width: 12),
                _stat('${learner.assessments}', 'Assessments'),
              ],
            ),
            const SizedBox(height: 16),
            ArrestoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Progress', style: ArrestoText.h4()),
                  const SizedBox(height: 12),
                  AnimatedArrestoProgressBar(
                    value: learner.progress / 100,
                    height: 10,
                  ),
                  const SizedBox(height: 4),
                  Text('${learner.progress}% complete across all courses',
                      style: ArrestoText.small()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ArrestoColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ArrestoColors.cardBorder),
        ),
        child: Column(
          children: [
            Text(value, style: ArrestoText.h3()),
            Text(label, style: ArrestoText.xs()),
          ],
        ),
      ),
    );
  }
}
