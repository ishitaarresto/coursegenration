import 'api_client.dart';

class AudioService {
  /// Returns the streaming URL for a lesson's audio (MP3).
  static String lessonAudioUrl(String scriptId, int moduleNumber, int lessonNumber) =>
      ApiClient.downloadUrl('/api/v1/audio/$scriptId/$moduleNumber/$lessonNumber');

  /// Lists all cached audio lessons for a script.
  static Future<Map<String, dynamic>> listAudio(String scriptId) async {
    final data = await ApiClient.get('/api/v1/audio/$scriptId');
    return data as Map<String, dynamic>;
  }

  /// Triggers background TTS pre-warm for all lessons in a script.
  static Future<String> generateAll(String scriptId) async {
    final data = await ApiClient.post('/api/v1/audio/generate/$scriptId', {});
    return (data as Map<String, dynamic>)['job_id'] as String;
  }

  /// Gets audio generation job status.
  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final data = await ApiClient.get('/api/v1/audio/jobs/$jobId');
    return data as Map<String, dynamic>;
  }
}
