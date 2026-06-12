import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/arresto_badge.dart';
import '../../../shared/widgets/arresto_card.dart';

class LearnersScreen extends StatelessWidget {
  const LearnersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Learners', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Manage your learners and their progress', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 28),

        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.4,
          children: const [
            StatCard(label: 'Total Learners',   value: '—', icon: Icons.people_rounded,         barColor: AColors.amber),
            StatCard(label: 'Active',            value: '—', icon: Icons.check_circle_rounded,   barColor: AColors.green),
            StatCard(label: 'Avg Progress',      value: '—', icon: Icons.trending_up_rounded,    barColor: AColors.blue),
            StatCard(label: 'Assessments Done',  value: '—', icon: Icons.quiz_rounded,           barColor: AColors.orange),
          ],
        ),
        const SizedBox(height: 28),

        APanel(
          title: 'Learner Management',
          subtitle: 'Connect authentication to manage learners',
          child: Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: Column(children: [
              const Icon(Icons.people_outline_rounded, size: 56, color: AColors.textMuted2),
              const SizedBox(height: 16),
              const Text('Learner accounts coming soon', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AColors.ink)),
              const SizedBox(height: 8),
              const Text('Connect an authentication system to manage learner accounts, track progress, and send invitations.',
                  style: TextStyle(fontSize: 13, color: AColors.textMuted), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ]),
    );
  }
}
