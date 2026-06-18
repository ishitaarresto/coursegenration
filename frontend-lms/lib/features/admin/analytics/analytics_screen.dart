import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/chip_group.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/providers/api_providers.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _tab = 'Course Generation';

  static const _tabs = [
    'Course Generation',
    'Content',
    'Learners',
    'AI Tutor',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArrestoColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.bar_chart_rounded,
              title: 'Analytics',
              subtitle: 'Platform performance overview',
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ChipGroup(
                options: _tabs,
                selected: _tab,
                onChanged: (v) => setState(() => _tab = v),
              ),
            ),
            const SizedBox(height: 20),
            if (_tab == 'Course Generation') _GenerationTab(),
            if (_tab == 'Learners') _LearnersTab(),
            if (_tab == 'Content') _ContentTab(),
            if (_tab == 'AI Tutor') _AITutorTab(),
          ],
        ),
      ),
    );
  }
}

class _GenerationTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(analyticsOverviewProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth > 800 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: 'Courses Generated',
                value: overview != null ? '${overview.totalCourses}' : '—',
                icon: Icons.auto_awesome_rounded,
                barColor: ArrestoColors.orange,
                iconColor: ArrestoColors.orange,
              ),
              StatCard(
                title: 'Videos Created',
                value: overview != null ? '${overview.totalVideos}' : '—',
                icon: Icons.videocam_rounded,
                barColor: ArrestoColors.blue,
                iconColor: ArrestoColors.blue,
              ),
              StatCard(
                title: 'Total Learners',
                value: overview != null ? '${overview.totalLearners}' : '—',
                icon: Icons.people_rounded,
                barColor: ArrestoColors.green,
                iconColor: ArrestoColors.green,
              ),
              StatCard(
                title: 'Active Learners',
                value: overview != null ? '${overview.activeLearners}' : '—',
                icon: Icons.person_rounded,
                barColor: ArrestoColors.amber,
                iconColor: ArrestoColors.amber,
              ),
              const StatCard(
                title: 'Avg Gen Time',
                value: '—',
                icon: Icons.timer_rounded,
                barColor: ArrestoColors.blue,
                iconColor: ArrestoColors.blue,
              ),
              const StatCard(
                title: 'AI Credits Used',
                value: '—',
                icon: Icons.token_rounded,
                barColor: ArrestoColors.textMuted,
                iconColor: ArrestoColors.textMuted,
              ),
            ],
          );
        }),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (ctx, c) {
          return c.maxWidth > 700
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _StyleBarChart(overview: overview)),
                    const SizedBox(width: 16),
                    Expanded(child: _GenerationLineChart()),
                  ],
                )
              : Column(children: [
                  _StyleBarChart(overview: overview),
                  const SizedBox(height: 16),
                  _GenerationLineChart(),
                ]);
        }),
      ],
    );
  }
}

class _StyleBarChart extends StatelessWidget {
  final AnalyticsOverview? overview;
  const _StyleBarChart({this.overview});

  static const _styleKeys = [
    ('modern',           'Free',       ArrestoColors.orange),
    ('animated_scene',   'Animated',   ArrestoColors.amber),
    ('whiteboard_doodle','Whiteboard', ArrestoColors.blue),
    ('hybrid',           'Hybrid',     ArrestoColors.green),
  ];

  @override
  Widget build(BuildContext context) {
    final dist = overview?.styleDistribution ?? {};
    final maxY = dist.values.isEmpty
        ? 10.0
        : (dist.values.reduce((a, b) => a > b ? a : b).toDouble() * 1.2)
            .clamp(10.0, double.infinity);

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < _styleKeys.length; i++) {
      final key   = _styleKeys[i].$1;
      final color = _styleKeys[i].$3;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (dist[key] ?? 0).toDouble(),
            color: color,
            width: 24,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      ));
    }

    return ArrestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Style Distribution', style: ArrestoText.h4()),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: ArrestoColors.line, strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < _styleKeys.length) {
                          return Text(_styleKeys[i].$2, style: ArrestoText.xs());
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) =>
                          Text('${v.toInt()}', style: ArrestoText.xs()),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerationLineChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Generation Over Time', style: ArrestoText.h4()),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: ArrestoColors.line, strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                        if (v.toInt() < months.length) {
                          return Text(months[v.toInt()],
                              style: ArrestoText.xs());
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) =>
                          Text('${v.toInt()}', style: ArrestoText.xs()),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 8),
                      FlSpot(1, 12),
                      FlSpot(2, 10),
                      FlSpot(3, 18),
                      FlSpot(4, 22),
                      FlSpot(5, 24),
                    ],
                    isCurved: true,
                    color: ArrestoColors.amber,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: ArrestoColors.amber.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LearnersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(analyticsOverviewProvider).valueOrNull;
    final activity = overview?.learnerActivity ?? [];
    final months   = activity.map((a) => a.month).toList();

    final spots = activity
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.count.toDouble()))
        .toList();

    final maxY = activity.isEmpty
        ? 10.0
        : (activity.map((a) => a.count).reduce((a, b) => a > b ? a : b).toDouble() * 1.3)
            .clamp(2.0, double.infinity);

    return ArrestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Learner Activity (last 6 months)', style: ArrestoText.h4()),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: ArrestoColors.line, strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < months.length) {
                          return Text(months[i], style: ArrestoText.xs());
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) =>
                          Text('${v.toInt()}', style: ArrestoText.xs()),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
                    isCurved: true,
                    color: ArrestoColors.blue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: ArrestoColors.blue.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      child: Text('Content analytics coming soon', style: ArrestoText.body()),
    );
  }
}

class _AITutorTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Tutor Usage', style: ArrestoText.h4()),
          const SizedBox(height: 12),
          Row(
            children: [
              _kpi('3,420', 'Total Conversations'),
              const SizedBox(width: 12),
              _kpi('4.8', 'Avg Rating'),
              const SizedBox(width: 12),
              _kpi('92%', 'Resolution Rate'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ArrestoColors.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ArrestoColors.line),
        ),
        child: Column(
          children: [
            Text(value, style: ArrestoText.h2()),
            Text(label, style: ArrestoText.xs(), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
