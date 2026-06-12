import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/arresto_badge.dart';
import '../../../shared/widgets/arresto_button.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: libraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => _Dashboard(items: items),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.items});
  final List<LibraryItem> items;

  @override
  Widget build(BuildContext context) {
    final totalLessons = items.fold(0, (s, i) => s + i.totalLessons);
    final totalMins = items.fold(0, (s, i) => s + i.estimatedDurationMin);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Page title
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Dashboard', style: AText.h1()),
          const SizedBox(height: 2),
          Text('Overview of your LMS', style: AText.body()),
        ])),
        AButton(
          label: 'Generate Course',
          icon: Icons.auto_awesome_rounded,
          onPressed: () => context.go('/admin/generator'),
        ),
      ]),
      const SizedBox(height: 28),

      // Stat grid
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.4,
        children: [
          StatCard(label: 'Total Courses', value: '${items.length}',
              icon: Icons.library_books_rounded, barColor: AColors.amber),
          StatCard(label: 'Total Lessons', value: '$totalLessons',
              icon: Icons.play_lesson_rounded, barColor: AColors.green),
          StatCard(label: 'Learning Hours', value: '${(totalMins / 60).toStringAsFixed(1)}h',
              icon: Icons.schedule_rounded, barColor: AColors.blue),
          StatCard(label: 'Learners', value: '—',
              icon: Icons.people_rounded, barColor: AColors.orange,
              sub: 'Coming soon'),
        ],
      ),
      const SizedBox(height: 28),

      // Recent courses table
      APanel(
        title: 'Recent Courses',
        subtitle: '${items.length} courses in library',
        action: TextButton(
          onPressed: () => context.go('/admin/courses'),
          child: const Text('View all', style: TextStyle(fontSize: 13, color: AColors.blue)),
        ),
        child: items.isEmpty
            ? _EmptyState()
            : Column(children: [
                // Header row
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text('COURSE',   style: AText.eyebrow())),
                    Expanded(child: Text('LESSONS',           style: AText.eyebrow())),
                    Expanded(child: Text('DURATION',          style: AText.eyebrow())),
                    Expanded(child: Text('FORMAT',            style: AText.eyebrow())),
                    const SizedBox(width: 80),
                  ]),
                ),
                const Divider(height: 1),
                ...items.take(8).map((item) => _CourseRow(item: item)),
              ]),
      ),
      const SizedBox(height: 24),

      // Quick actions
      Row(children: [
        Expanded(child: _QuickAction(
          icon: Icons.upload_rounded,
          label: 'Upload Document',
          onTap: () => context.go('/admin/generator'),
        )),
        const SizedBox(width: 16),
        Expanded(child: _QuickAction(
          icon: Icons.people_rounded,
          label: 'Manage Learners',
          onTap: () => context.go('/admin/learners'),
        )),
        const SizedBox(width: 16),
        Expanded(child: _QuickAction(
          icon: Icons.bar_chart_rounded,
          label: 'View Analytics',
          onTap: () => context.go('/admin/analytics'),
        )),
        const SizedBox(width: 16),
        Expanded(child: _QuickAction(
          icon: Icons.settings_rounded,
          label: 'Settings',
          onTap: () => context.go('/admin/settings'),
        )),
      ]),
    ]);
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.item});
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch((item.generatedAt * 1000).toInt());
    final dateStr = DateFormat('MMM d, yyyy').format(dt);
    return InkWell(
      onTap: () => context.go('/admin/courses/${item.scriptId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.courseTitle,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(item.sourceFile,
                style: const TextStyle(fontSize: 11, color: AColors.textMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Expanded(child: Text('${item.totalLessons}',
              style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
          Expanded(child: Text('${item.estimatedDurationMin}m',
              style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
          Expanded(child: ABadge(item.sourceFile.endsWith('.pptx') ? 'Slides' : 'Standard',
              variant: ABadgeVariant.blue)),
          SizedBox(
            width: 80,
            child: TextButton(
              onPressed: () => context.go('/admin/courses/${item.scriptId}'),
              child: const Text('View', style: TextStyle(fontSize: 12, color: AColors.blue)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ACard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AColors.bg2, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: AColors.ink),
        ),
        const SizedBox(height: 8),
        Text(label, style: AText.smallBold(), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(child: Column(children: [
        const Icon(Icons.library_books_outlined, size: 48, color: AColors.textMuted2),
        const SizedBox(height: 12),
        Text('No courses yet', style: AText.h3()),
        const SizedBox(height: 6),
        Text('Generate your first course using the Course Generator', style: AText.body()),
        const SizedBox(height: 16),
        AButton(label: 'Generate Course', icon: Icons.auto_awesome_rounded,
            onPressed: () => context.go('/admin/generator')),
      ])),
    );
  }
}
