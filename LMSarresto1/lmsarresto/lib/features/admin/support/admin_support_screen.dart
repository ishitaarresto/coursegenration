import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_badge.dart';
import '../../../shared/widgets/stat_card.dart';

class AdminSupportScreen extends StatelessWidget {
  const AdminSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Support', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Manage learner support requests', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 28),

        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.4,
          children: const [
            StatCard(label: 'Total Requests', value: '0', icon: Icons.inbox_rounded, barColor: AColors.amber),
            StatCard(label: 'Open', value: '0', icon: Icons.radio_button_checked_rounded, barColor: AColors.orange),
            StatCard(label: 'In Progress', value: '0', icon: Icons.pending_rounded, barColor: AColors.blue),
            StatCard(label: 'Resolved', value: '0', icon: Icons.check_circle_rounded, barColor: AColors.green),
          ],
        ),
        const SizedBox(height: 28),

        APanel(
          title: 'Support Tickets',
          child: Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: const Column(children: [
              Icon(Icons.headset_mic_outlined, size: 56, color: AColors.textMuted2),
              SizedBox(height: 16),
              Text('No support tickets yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AColors.ink)),
              SizedBox(height: 8),
              Text('Support tickets submitted by learners will appear here.',
                  style: TextStyle(fontSize: 13, color: AColors.textMuted), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ]),
    );
  }
}
