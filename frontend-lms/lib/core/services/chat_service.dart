import 'api_client.dart';
import '../../features/shared/arresto_ai/arresto_ai_panel.dart' show AiLessonContext;

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
}
