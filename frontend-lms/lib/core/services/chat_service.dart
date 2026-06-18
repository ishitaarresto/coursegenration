import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'api_client.dart';
import '../config/api_config.dart';
import '../../features/shared/arresto_ai/arresto_ai_panel.dart' show AiLessonContext;

class VoiceChatResult {
  final String transcription;
  final String answer;
  final String? audioUrl;
  const VoiceChatResult({
    required this.transcription,
    required this.answer,
    this.audioUrl,
  });
}

class ChatService {
  /// Ask a question using the RAG endpoint.
  /// Pass [lessonContext] when calling from inside a lesson player so the
  /// backend can answer about the current lesson specifically.
  /// Pass [history] (last N turns) to enable multi-turn conversation.
  static Future<String> ask(
    String question, {
    String? sourceFile,
    int nChunks = 5,
    AiLessonContext? lessonContext,
    List<Map<String, String>>? history,
  }) async {
    final resp = await apiClient.post('/api/v1/chat', data: {
      'question': question,
      if (sourceFile != null) 'source_file': sourceFile,
      'n_chunks': nChunks,
      if (history != null && history.isNotEmpty) 'history': history,
      if (lessonContext != null) ...{
        'lesson_id':          lessonContext.lessonId,
        'course_id':          lessonContext.courseId,
        'timestamp_secs':     lessonContext.timestampSecs,
        if (lessonContext.transcript != null)
          'transcript_snippet': lessonContext.transcript,
      },
    });
    return resp.data['answer'] as String;
  }

  /// Full voice round-trip: audio → Sarvam STT → RAG knowledge base → Sarvam TTS.
  /// Returns transcription, Claude's answer, and an optional audio URL to auto-play.
  static Future<VoiceChatResult> voiceChat(
    Uint8List audioBytes, {
    AiLessonContext? lessonContext,
    List<Map<String, String>>? history,
  }) async {
    final formData = FormData.fromMap({
      'audio': MultipartFile.fromBytes(
        audioBytes,
        filename: 'recording.webm',
        contentType: DioMediaType('audio', 'webm'),
      ),
      if (lessonContext != null) ...{
        'lesson_id':      lessonContext.lessonId,
        'course_id':      lessonContext.courseId,
        'timestamp_secs': lessonContext.timestampSecs.toString(),
      },
      if (history != null && history.isNotEmpty) 'history': jsonEncode(history),
    });

    final resp = await apiClient.post(
      '/api/v1/voice/chat',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(seconds: 90),
      ),
    );

    final relUrl = resp.data['audio_url'] as String?;
    return VoiceChatResult(
      transcription: resp.data['transcription'] as String,
      answer:        resp.data['answer'] as String,
      audioUrl:      relUrl != null ? '${ApiConfig.baseUrl}$relUrl' : null,
    );
  }

  /// Send a mic recording (webm bytes) to the backend Sarvam STT endpoint.
  /// Returns the transcribed text, or empty string on silence.
  static Future<String> transcribeAudio(Uint8List audioBytes) async {
    final formData = FormData.fromMap({
      'audio': MultipartFile.fromBytes(
        audioBytes,
        filename: 'recording.webm',
        contentType: DioMediaType('audio', 'webm'),
      ),
    });
    final resp = await apiClient.post(
      '/api/v1/voice/transcribe',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    return resp.data['text'] as String? ?? '';
  }
}
