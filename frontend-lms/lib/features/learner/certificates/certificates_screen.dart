import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/services/assessment_service.dart';
import '../../../data/providers/api_providers.dart';

class CertificatesScreen extends ConsumerWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(assessmentHistoryProvider);

    return RefreshIndicator(
      color: ArrestoColors.orange,
      onRefresh: () async => ref.invalidate(assessmentHistoryProvider),
      child: historyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ArrestoColors.orange),
        ),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded,
                color: ArrestoColors.textMuted2, size: 40),
            const SizedBox(height: 12),
            Text('Could not load certificates', style: ArrestoText.body()),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(assessmentHistoryProvider),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (history) {
          // One certificate per unique course where the learner passed at least once.
          // Keep the best (highest score) passing attempt per course.
          final Map<String, AssessmentHistoryItem> bestByCoure = {};
          for (final item in history) {
            if (!item.passed) continue;
            final existing = bestByCoure[item.courseId];
            if (existing == null || item.score > existing.score) {
              bestByCoure[item.courseId] = item;
            }
          }
          final certs = bestByCoure.values.toList()
            ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  icon: Icons.workspace_premium_rounded,
                  title: 'My Certificates',
                  subtitle: '${certs.length} certificate${certs.length != 1 ? 's' : ''} earned',
                ),
                const SizedBox(height: 20),
                if (certs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 40, horizontal: 24),
                    decoration: BoxDecoration(
                      color: ArrestoColors.bg2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ArrestoColors.line),
                    ),
                    child: Column(children: [
                      const Icon(Icons.workspace_premium_outlined,
                          size: 48, color: ArrestoColors.textMuted2),
                      const SizedBox(height: 12),
                      Text('No certificates yet',
                          style: ArrestoText.bodyBold(
                              color: ArrestoColors.textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        'Pass an assessment to earn your first certificate.',
                        style: ArrestoText.small(),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  )
                else
                  ...certs.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _CertificateCard(item: c),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final AssessmentHistoryItem item;
  const _CertificateCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final certId = 'CERT-${item.id.substring(0, 8).toUpperCase()}';

    return Container(
      decoration: BoxDecoration(
        color: ArrestoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ArrestoColors.amber, width: 2),
        boxShadow: ArrestoColors.sh2,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ArrestoColors.amber,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('A',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: ArrestoColors.ink)),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ARRESTO LMS',
                        style: ArrestoText.eyebrow(color: ArrestoColors.ink)
                            .copyWith(letterSpacing: 1.5)),
                    Text('Accredited Training Provider',
                        style: ArrestoText.xs()),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ArrestoColors.greenSoft,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ArrestoColors.green),
                  ),
                  child: Text('${item.score}% Pass',
                      style: ArrestoText.xs(color: ArrestoColors.green)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: ArrestoColors.line),
            const SizedBox(height: 12),

            // Certificate body
            Text(
              'CERTIFICATE OF COMPLETION',
              style: ArrestoText.eyebrow(color: ArrestoColors.orange)
                  .copyWith(letterSpacing: 2),
            ),
            const SizedBox(height: 8),
            Text(item.courseTitle, style: ArrestoText.h2()),
            const SizedBox(height: 12),
            Row(
              children: [
                _info('Issue Date', item.formattedDate),
                const SizedBox(width: 24),
                _info('Certificate ID', certId),
                const SizedBox(width: 24),
                _info('Score', '${item.score}%'),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: ArrestoColors.line),
            const SizedBox(height: 12),

            // Actions
            Row(
              children: [
                ArrestoButton(
                  label: 'Download PDF',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Certificate download coming soon.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                ArrestoButton(
                  label: 'Share',
                  variant: ArrestoButtonVariant.ghost,
                  icon: const Icon(Icons.share_rounded),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share feature coming soon.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ArrestoText.xs()),
        Text(value,
            style: ArrestoText.small(color: ArrestoColors.ink)
                .copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
