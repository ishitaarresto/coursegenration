import 'api_client.dart';
import '../../data/models/learner.dart';

class ProfileData {
  final String learnerId;
  final String displayName;
  final String email;
  final int enrolledCourses;
  final int completedLessons;
  final int certificates;
  final String? avatarUrl;

  const ProfileData({
    required this.learnerId,
    required this.displayName,
    required this.email,
    required this.enrolledCourses,
    required this.completedLessons,
    required this.certificates,
    this.avatarUrl,
  });

  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
        learnerId:        j['learner_id']        as String,
        displayName:      j['display_name']      as String,
        email:            j['email']             as String,
        enrolledCourses:  j['enrolled_courses']  as int,
        completedLessons: j['completed_lessons'] as int,
        certificates:     j['certificates']      as int,
        avatarUrl:        j['avatar_url']        as String?,
      );
}

class LearnerService {
  static Future<ProfileData> getProfile(String learnerId) async {
    final resp = await apiClient.get('/api/v1/profile/$learnerId');
    return ProfileData.fromJson(resp.data as Map<String, dynamic>);
  }

  static Future<void> updateDisplayName(String learnerId, String name) async {
    await apiClient.patch(
      '/api/v1/profile/$learnerId',
      data: {'display_name': name},
    );
  }

  static Future<List<Learner>> listLearners() async {
    final resp = await apiClient.get('/api/v1/learners');
    final list = resp.data as List;
    return list
        .map((e) => Learner.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Learner> getLearnerDetail(String learnerId) async {
    final resp = await apiClient.get('/api/v1/learners/$learnerId');
    return Learner.fromJson(resp.data as Map<String, dynamic>);
  }
}
