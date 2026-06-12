import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/colors.dart';
import '../../../core/providers/library_provider.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/stat_card.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _tab = 0;
  static const _tabs = ['Course Generation', 'Content', 'Learners', 'AI Tutor'];

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Analytics', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Insights across your LMS', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 24),

        // Tab bar
        ACard(
          padding: const EdgeInsets.all(4),
          child: Row(children: List.generate(_tabs.length, (i) => Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _tab == i ? AColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_tabs[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: _tab == i ? Colors.white : AColors.textMuted)),
              ),
            ),
          ))),
        ),
        const SizedBox(height: 24),

        libraryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (items) => _tab == 0 ? _CourseGenTab(items: items) : _ComingSoon(_tabs[_tab]),
        ),
      ]),
    );
  }
}

class _CourseGenTab extends StatelessWidget {
  const _CourseGenTab({required this.items});
  final List items;

  @override
  Widget build(BuildContext context) {
    final totalLessons = items.fold<int>(0, (s, i) => s + (i.totalLessons as int));
    final totalMins = items.fold<int>(0, (s, i) => s + (i.estimatedDurationMin as int));

    // Sort by generatedAt (unix epoch seconds as double) ascending
    final sorted = [...items]..sort((a, b) =>
        (a.generatedAt as double).compareTo(b.generatedAt as double));

    // Build cumulative spots using days relative to first item
    final List<FlSpot> spots;
    List<String> bottomLabels = [];
    if (sorted.isNotEmpty) {
      final firstTs = sorted.first.generatedAt as double;
      spots = [];
      bottomLabels = [];
      for (int i = 0; i < sorted.length; i++) {
        final dayOffset = ((sorted[i].generatedAt as double) - firstTs) / 86400;
        spots.add(FlSpot(dayOffset, (i + 1).toDouble()));
        // Label for every ~5th item or first/last
        final dt = DateTime.fromMillisecondsSinceEpoch(
            ((sorted[i].generatedAt as double) * 1000).toInt());
        bottomLabels.add('${dt.day}/${dt.month}');
      }
    } else {
      spots = [];
    }

    return Column(children: [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.5,
        children: [
          StatCard(label: 'Courses Generated', value: '${items.length}',
              icon: Icons.library_books_rounded, barColor: AColors.amber),
          StatCard(label: 'Total Lessons', value: '$totalLessons',
              icon: Icons.play_lesson_rounded, barColor: AColors.green),
          StatCard(label: 'Learning Hours', value: '${(totalMins / 60).toStringAsFixed(1)}h',
              icon: Icons.schedule_rounded, barColor: AColors.blue),
        ],
      ),
      const SizedBox(height: 24),

      APanel(
        title: 'Course Generation Over Time',
        subtitle: 'Cumulative courses generated (x = days from first course)',
        child: SizedBox(
          height: 200,
          child: sorted.isEmpty
              ? const Center(child: Text('No data yet', style: TextStyle(color: AColors.textMuted)))
              : LineChart(LineChartData(
                  gridData: FlGridData(show: true, getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AColors.cardBorder, strokeWidth: 1)),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 30,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}',
                          style: const TextStyle(fontSize: 10, color: AColors.textMuted)),
                    )),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: sorted.length <= 10,
                      reservedSize: 22,
                      getTitlesWidget: (v, meta) {
                        // Find closest spot
                        final idx = spots.indexWhere((s) => (s.x - v).abs() < 0.5);
                        if (idx < 0 || idx >= bottomLabels.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(bottomLabels[idx],
                              style: const TextStyle(fontSize: 9, color: AColors.textMuted)),
                        );
                      },
                    )),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AColors.amber,
                      barWidth: 2,
                      dotData: FlDotData(show: sorted.length <= 15),
                      belowBarData: BarAreaData(show: true, color: AColors.amber.withValues(alpha: 0.1)),
                    ),
                  ],
                )),
        ),
      ),

      if (sorted.isNotEmpty) ...[
        const SizedBox(height: 24),
        APanel(
          title: 'Course List',
          child: Column(children: sorted.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AColors.amberSoft, shape: BoxShape.circle),
                child: Center(child: Text('${e.key + 1}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AColors.orange))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(e.value.courseTitle as String,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${e.value.totalLessons} lessons',
                  style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
            ]),
          )).toList()),
        ),
      ],
    ]);
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon(this.tab);
  final String tab;

  @override
  Widget build(BuildContext context) {
    return ACard(
      child: Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: Column(children: [
          const Icon(Icons.bar_chart_rounded, size: 56, color: AColors.textMuted2),
          const SizedBox(height: 16),
          Text('$tab Analytics', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AColors.ink)),
          const SizedBox(height: 8),
          const Text('Coming soon — requires learner authentication and activity tracking.',
              style: TextStyle(fontSize: 13, color: AColors.textMuted), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
