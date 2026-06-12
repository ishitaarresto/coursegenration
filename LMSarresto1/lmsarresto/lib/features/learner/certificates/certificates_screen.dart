import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/stat_card.dart';

class CertificatesScreen extends StatelessWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Certificates', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Your earned certifications', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 28),

        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.6,
          children: const [
            StatCard(label: 'Earned', value: '0', icon: Icons.workspace_premium_rounded, barColor: AColors.amber),
            StatCard(label: 'In Progress', value: '0', icon: Icons.pending_outlined, barColor: AColors.blue),
            StatCard(label: 'Expired', value: '0', icon: Icons.schedule_rounded, barColor: AColors.red),
          ],
        ),
        const SizedBox(height: 28),

        APanel(
          title: 'My Certificates',
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AColors.amberSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, size: 44, color: AColors.amber),
                ),
                const SizedBox(height: 16),
                const Text('No certificates yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AColors.ink)),
                const SizedBox(height: 8),
                const Text('Complete a course and pass the assessment to earn your certificate.',
                    style: TextStyle(fontSize: 13, color: AColors.textMuted), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
