import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/course_thumb.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../data/providers/app_state.dart';
import '../../../data/providers/api_providers.dart';

String _formattedToday() {
  final now = DateTime.now();
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
}

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider);
    final isWide = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: ArrestoColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Admin Dashboard', style: ArrestoText.h1()),
                      Text(_formattedToday(), style: ArrestoText.small()),
                    ],
                  ),
                ),
                ArrestoButton(
                  label: 'Generate Course',
                  icon: const Icon(Icons.auto_awesome_rounded),
                  onPressed: () => context.go('/admin/generator'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stats grid
            _AdminStatsGrid(),
            const SizedBox(height: 20),

            // Quick actions
            _QuickActions(),
            const SizedBox(height: 20),

            // Main + sidebar
            isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _CourseTable(courses: courses)),
                      const SizedBox(width: 20),
                      SizedBox(width: 300, child: _AdminSidebar()),
                    ],
                  )
                : Column(
                    children: [
                      _CourseTable(courses: courses),
                      const SizedBox(height: 20),
                      _AdminSidebar(),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class _AdminStatsGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    final courseCount = libraryAsync.maybeWhen(
      data: (courses) => courses.length.toString(),
      orElse: () => '—',
    );
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 1000 ? 4 : c.maxWidth > 600 ? 3 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          const StatCard(
            title: 'Total Learners',
            value: '1,284',
            icon: Icons.people_rounded,
            iconColor: ArrestoColors.blue,
            barColor: ArrestoColors.blue,
          ),
          StatCard(
            title: 'Total Courses',
            value: courseCount,
            icon: Icons.library_books_rounded,
            iconColor: ArrestoColors.amber,
            barColor: ArrestoColors.amber,
          ),
          const StatCard(
            title: 'Active Learners',
            value: '1,042',
            sub: '81% of total',
            icon: Icons.person_rounded,
            iconColor: ArrestoColors.green,
            barColor: ArrestoColors.green,
          ),
          const StatCard(
            title: 'Courses Generated',
            value: '47',
            icon: Icons.auto_awesome_rounded,
            iconColor: ArrestoColors.orange,
            barColor: ArrestoColors.orange,
          ),
          const StatCard(
            title: 'Learning Hours',
            value: '18.2k',
            icon: Icons.schedule_rounded,
            iconColor: ArrestoColors.blue,
            barColor: ArrestoColors.blue,
          ),
          const StatCard(
            title: 'AI Conversations',
            value: '3,420',
            icon: Icons.chat_rounded,
            iconColor: ArrestoColors.amber,
            barColor: ArrestoColors.amber,
          ),
          const StatCard(
            title: 'Generating Now',
            value: '2',
            sub: 'In progress',
            icon: Icons.sync_rounded,
            iconColor: ArrestoColors.red,
            barColor: ArrestoColors.red,
          ),
        ],
      );
    });
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ArrestoButton(
          label: 'Generate Course',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => context.go('/admin/generator'),
        ),
        ArrestoButton(
          label: 'Invite Learner',
          variant: ArrestoButtonVariant.ghost,
          icon: const Icon(Icons.person_add_rounded),
          onPressed: () => context.go('/admin/learners'),
        ),
        ArrestoButton(
          label: 'View Analytics',
          variant: ArrestoButtonVariant.ghost,
          icon: const Icon(Icons.bar_chart_rounded),
          onPressed: () => context.go('/admin/analytics'),
        ),
        ArrestoButton(
          label: 'Support Tickets',
          variant: ArrestoButtonVariant.ghost,
          icon: const Icon(Icons.support_agent_rounded),
          onPressed: () => context.go('/admin/support'),
        ),
      ],
    );
  }
}

class _CourseTable extends StatelessWidget {
  final List courses;
  const _CourseTable({required this.courses});

  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  icon: Icons.library_books_rounded,
                  title: 'All Courses',
                ),
              ),
              ArrestoButton(
                label: 'View All',
                variant: ArrestoButtonVariant.ghost,
                size: ArrestoButtonSize.sm,
                onPressed: () => context.go('/admin/courses'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Course',
                        style: ArrestoText.smallBold())),
                Expanded(
                    child: Text('Style',
                        style: ArrestoText.smallBold())),
                Expanded(
                    child: Text('Status',
                        style: ArrestoText.smallBold())),
                Expanded(
                    child: Text('Learners',
                        style: ArrestoText.smallBold())),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(color: ArrestoColors.line, height: 1),
          ...courses.map((course) => _CourseRow(course: course)),
        ],
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  final dynamic course;
  const _CourseRow({required this.course});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ArrestoColors.line, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CourseThumb(
                    style: course.style, code: null, height: 36),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                      style: ArrestoText.bodyBold(),
                      overflow: TextOverflow.ellipsis),
                  Text(course.code,
                      style: ArrestoText.xs()),
                ],
              ),
            ),
            Expanded(
              child: Text(
                switch (course.style as CourseStyle) {
                  CourseStyle.animated   => 'Animated',
                  CourseStyle.whiteboard => 'Whiteboard',
                  CourseStyle.claude     => 'AI Style',
                  CourseStyle.hybrid     => 'Hybrid',
                },
                style: ArrestoText.small(),
              ),
            ),
            Expanded(child: StatusBadge(status: course.status)),
            Expanded(
              child: Text('${course.learners}',
                  style: ArrestoText.bodySm(
                      color: ArrestoColors.ink)),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  size: 16, color: ArrestoColors.textMuted),
              onPressed: () => context.go('/admin/courses'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Recent activity
        ArrestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Activity', style: ArrestoText.h4()),
              const SizedBox(height: 12),
              ...[
                ('🎓', 'James Harrington completed WAH-181', '2h ago'),
                ('🤖', 'Scaffolding Safety course generated', '4h ago'),
                ('📋', 'New ticket TK-1042 opened', '5h ago'),
                ('✅', 'Priya Nair passed Assessment 3', '1d ago'),
              ].map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(item.$2,
                              style: ArrestoText.bodySm(
                                  color: ArrestoColors.ink))),
                      const SizedBox(width: 6),
                      Text(item.$3, style: ArrestoText.xs()),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Generation queue
        ArrestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generation Queue', style: ArrestoText.h4()),
              const SizedBox(height: 12),
              ...[
                ('Rope Access Safety', 0.7),
                ('PPE Selection Guide', 0.3),
              ].map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(item.$1,
                                  style: ArrestoText.bodySm(
                                      color: ArrestoColors.ink))),
                          Text(
                              '${(item.$2 * 100).round()}%',
                              style: ArrestoText.small()),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedArrestoProgressBar(
                        value: item.$2,
                        tone: ProgressTone.orange,
                        height: 6,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // AI builder CTA
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ArrestoColors.ink,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        ArrestoColors.amber,
                        ArrestoColors.orange
                      ]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        size: 17, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text('AI Course Builder',
                      style: ArrestoText.h4(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Generate a full course in under 5 minutes.',
                  style: ArrestoText.small(color: Colors.white60)),
              const SizedBox(height: 12),
              ArrestoButton(
                label: 'Generate Now',
                onPressed: () => context.go('/admin/generator'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
