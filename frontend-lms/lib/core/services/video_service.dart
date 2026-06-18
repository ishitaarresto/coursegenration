import 'api_client.dart';

class VideoRenderJob {
  final String renderId;
  final String scriptId;
  final String lessonRef;
  final String lang;
  final String style;
  final String status;     // pending | processing | completed | failed
  final String ttsEngine;
  final String? error;
  final double startedAt;
  final double? finishedAt;
  final bool videoReady;

  const VideoRenderJob({
    required this.renderId,
    required this.scriptId,
    required this.lessonRef,
    required this.lang,
    required this.style,
    required this.status,
    required this.ttsEngine,
    this.error,
    required this.startedAt,
    this.finishedAt,
    required this.videoReady,
  });

  factory VideoRenderJob.fromJson(Map<String, dynamic> j) => VideoRenderJob(
        renderId:   j['render_id'] as String,
        scriptId:   j['script_id'] as String,
        lessonRef:  j['lesson_ref'] as String,
        lang:       j['lang'] as String? ?? 'en',
        style:      j['style'] as String? ?? 'animated_scene',
        status:     j['status'] as String,
        ttsEngine:  j['tts_engine'] as String? ?? '',
        error:      j['error'] as String?,
        startedAt:  (j['started_at'] as num).toDouble(),
        finishedAt: (j['finished_at'] as num?)?.toDouble(),
        videoReady: j['video_ready'] as bool? ?? false,
      );
}

class VideoService {
  /// Trigger video renders for every lesson in a course.
  /// Returns the number of jobs started (already-completed lessons are skipped).
  static Future<int> generateAll(
    String scriptId, {
    String style = 'modern',
    String lang = 'en',
  }) async {
    final resp = await apiClient.post(
      '/api/v1/video/generate-all/$scriptId',
      queryParameters: {'style': style, 'lang': lang},
    );
    return (resp.data['jobs_started'] as num).toInt();
  }

  /// List all render jobs for a course.
  static Future<List<VideoRenderJob>> listRenders(String scriptId) async {
    final resp = await apiClient.get('/api/v1/video/scripts/$scriptId/renders');
    final list = resp.data['renders'] as List;
    return list
        .map((j) => VideoRenderJob.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Poll a single render job.
  static Future<VideoRenderJob> getRenderStatus(String renderId) async {
    final resp = await apiClient.get('/api/v1/video/renders/$renderId');
    return VideoRenderJob.fromJson(resp.data as Map<String, dynamic>);
  }
}
