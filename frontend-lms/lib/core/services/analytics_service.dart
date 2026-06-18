import 'api_client.dart';

class MonthlyActivity {
  final String month;
  final int count;

  const MonthlyActivity({required this.month, required this.count});

  factory MonthlyActivity.fromJson(Map<String, dynamic> j) => MonthlyActivity(
        month: j['month'] as String,
        count: j['count'] as int,
      );
}

class AnalyticsOverview {
  final int totalCourses;
  final int totalVideos;
  final int totalLearners;
  final int activeLearners;
  final List<MonthlyActivity> learnerActivity;
  final Map<String, int> styleDistribution;

  const AnalyticsOverview({
    required this.totalCourses,
    required this.totalVideos,
    required this.totalLearners,
    required this.activeLearners,
    required this.learnerActivity,
    required this.styleDistribution,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> j) =>
      AnalyticsOverview(
        totalCourses:   j['total_courses']  as int,
        totalVideos:    j['total_videos']   as int,
        totalLearners:  j['total_learners'] as int,
        activeLearners: j['active_learners'] as int,
        learnerActivity: (j['learner_activity'] as List)
            .map((e) => MonthlyActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
        styleDistribution: (j['style_distribution'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      );
}

class AnalyticsService {
  static Future<AnalyticsOverview> getOverview() async {
    final resp = await apiClient.get('/api/v1/analytics/overview');
    return AnalyticsOverview.fromJson(resp.data as Map<String, dynamic>);
  }
}
