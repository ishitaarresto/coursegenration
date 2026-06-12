// All API data models used throughout the app.

class LibraryItem {
  final String scriptId;
  final String sourceFile;
  final String courseTitle;
  final String targetAudience;
  final double generatedAt;
  final int totalLessons;
  final int estimatedDurationMin;
  final String? instructions;

  const LibraryItem({
    required this.scriptId,
    required this.sourceFile,
    required this.courseTitle,
    required this.targetAudience,
    required this.generatedAt,
    required this.totalLessons,
    required this.estimatedDurationMin,
    this.instructions,
  });

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        scriptId: j['script_id'] as String,
        sourceFile: j['source_file'] as String,
        courseTitle: j['course_title'] as String? ?? 'Untitled',
        targetAudience: j['target_audience'] as String? ?? 'Learners',
        generatedAt: (j['generated_at'] as num).toDouble(),
        totalLessons: (j['total_lessons'] as num?)?.toInt() ?? 0,
        estimatedDurationMin: (j['estimated_duration_min'] as num?)?.toInt() ?? 0,
        instructions: j['instructions'] as String?,
      );

  String get category {
    final t = courseTitle.toLowerCase();
    if (t.contains('fall') || t.contains('height')) return 'FALL PROTECTION';
    if (t.contains('equip') || t.contains('tool')) return 'EQUIPMENT';
    if (t.contains('emergency') || t.contains('first aid')) return 'EMERGENCY';
    return 'SITE SAFETY';
  }
}

class CourseScript {
  final String scriptId;
  final String title;
  final String description;
  final List<String> objectives;
  final List<CourseModule> modules;
  final List<CourseItem> items;
  final bool isCustom;

  const CourseScript({
    required this.scriptId,
    required this.title,
    required this.description,
    required this.objectives,
    required this.modules,
    required this.items,
    required this.isCustom,
  });

  factory CourseScript.fromJson(Map<String, dynamic> j) {
    final script = j['course_script'] as Map<String, dynamic>? ?? j;
    final rawItems = script['items'] as List?;
    final isCustom = rawItems != null && rawItems.isNotEmpty;
    return CourseScript(
      scriptId: j['script_id'] as String? ?? script['script_id'] as String? ?? '',
      title: script['title'] as String? ?? script['course_title'] as String? ?? 'Untitled',
      description: script['description'] as String? ?? '',
      objectives: List<String>.from(script['learning_objectives'] as List? ?? []),
      modules: isCustom ? [] : (script['modules'] as List? ?? [])
          .map((m) => CourseModule.fromJson(m as Map<String, dynamic>))
          .toList(),
      items: isCustom ? (rawItems ?? [])
          .map((i) => CourseItem.fromJson(i as Map<String, dynamic>))
          .toList() : [],
      isCustom: isCustom,
    );
  }
}

class CourseModule {
  final int moduleNumber;
  final String title;
  final List<CourseLesson> lessons;

  const CourseModule({required this.moduleNumber, required this.title, required this.lessons});

  factory CourseModule.fromJson(Map<String, dynamic> j) => CourseModule(
        moduleNumber: (j['module_number'] as num?)?.toInt() ?? 1,
        title: j['module_title'] as String? ?? j['title'] as String? ?? '',
        lessons: (j['lessons'] as List? ?? [])
            .map((l) => CourseLesson.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

class CourseSlide {
  final int slideNumber;
  final List<String> bullets;
  const CourseSlide({required this.slideNumber, required this.bullets});

  factory CourseSlide.fromJson(Map<String, dynamic> j) => CourseSlide(
        slideNumber: (j['slide_number'] as num?)?.toInt() ?? 1,
        bullets: List<String>.from(j['bullets'] as List? ?? []),
      );
}

class CourseLesson {
  final int lessonNumber;
  final String title;
  final String summary;
  final String narration;
  final String narrationScript;
  final List<CourseSlide> slides;
  final List<String> keyTakeaways;
  final List<String> bullets;
  final List<Map<String, dynamic>> quizQuestions;

  const CourseLesson({
    required this.lessonNumber,
    required this.title,
    required this.summary,
    required this.narration,
    required this.narrationScript,
    required this.slides,
    required this.keyTakeaways,
    required this.bullets,
    this.quizQuestions = const [],
  });

  factory CourseLesson.fromJson(Map<String, dynamic> j) {
    final slideContent = j['slide_content'];
    List<CourseSlide> slides;
    List<String> contentBullets;

    if (slideContent is List) {
      slides = slideContent
          .map((s) => CourseSlide.fromJson(s as Map<String, dynamic>))
          .toList();
      contentBullets = List<String>.from(j['slide_bullets'] as List? ?? []);
    } else if (slideContent is Map) {
      // Standard format: slide_content is {title, bullets, speaker_notes}
      final bullets = List<String>.from(slideContent['bullets'] as List? ?? []);
      slides = bullets.isNotEmpty ? [CourseSlide(slideNumber: 1, bullets: bullets)] : [];
      contentBullets = bullets;
    } else {
      slides = [];
      contentBullets = List<String>.from(j['slide_bullets'] as List? ?? []);
    }

    return CourseLesson(
      lessonNumber: (j['lesson_number'] as num?)?.toInt() ?? 1,
      title: j['lesson_title'] as String? ?? j['title'] as String? ?? '',
      summary: j['summary'] as String? ?? '',
      narration: j['narration_script'] as String? ?? j['narration'] as String? ?? '',
      narrationScript: j['narration_script'] as String? ?? j['narration'] as String? ?? '',
      slides: slides,
      keyTakeaways: List<String>.from(j['key_takeaways'] as List? ?? []),
      bullets: contentBullets,
      quizQuestions: (j['quiz_questions'] as List? ?? [])
          .map((q) => q as Map<String, dynamic>).toList(),
    );
  }
}

class CourseItem {
  final String type;
  final String title;
  final String narration;
  final List<String> bullets;
  final Map<String, dynamic> raw;

  const CourseItem({
    required this.type,
    required this.title,
    required this.narration,
    required this.bullets,
    required this.raw,
  });

  factory CourseItem.fromJson(Map<String, dynamic> j) => CourseItem(
        type: j['type'] as String? ?? 'slide',
        title: j['title'] as String? ?? '',
        narration: j['narration'] as String? ?? j['narration_script'] as String? ?? '',
        bullets: List<String>.from(j['bullets'] as List? ?? []),
        raw: j,
      );
}

class JobStatus {
  final String jobId;
  final String status;
  final int progress;
  final String step;
  final String? error;
  final Map<String, dynamic>? courseScript;

  const JobStatus({
    required this.jobId,
    required this.status,
    required this.progress,
    required this.step,
    this.error,
    this.courseScript,
  });

  factory JobStatus.fromJson(Map<String, dynamic> j) => JobStatus(
        jobId: j['job_id'] as String,
        status: j['status'] as String,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        step: j['step'] as String? ?? '',
        error: j['error'] as String?,
        courseScript: j['course_script'] as Map<String, dynamic>?,
      );

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isDone => isCompleted || isFailed;
}

class VideoRender {
  final String renderId;
  final String scriptId;
  final String lessonRef;
  final String lang;
  final String style;
  final String status;
  final bool videoReady;
  final String? error;

  const VideoRender({
    required this.renderId,
    required this.scriptId,
    required this.lessonRef,
    required this.lang,
    required this.style,
    required this.status,
    required this.videoReady,
    this.error,
  });

  factory VideoRender.fromJson(Map<String, dynamic> j) => VideoRender(
        renderId: j['render_id'] as String,
        scriptId: j['script_id'] as String,
        lessonRef: j['lesson_ref'] as String? ?? '',
        lang: j['lang'] as String? ?? 'en',
        style: j['style'] as String? ?? 'modern',
        status: j['status'] as String,
        videoReady: j['video_ready'] as bool? ?? false,
        error: j['error'] as String?,
      );

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isDone => isCompleted || isFailed;
}

class DocumentInfo {
  final String sourceFile;
  final int chunkCount;
  final String assetType;

  const DocumentInfo({
    required this.sourceFile,
    required this.chunkCount,
    required this.assetType,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> j) => DocumentInfo(
        sourceFile: j['source_file'] as String,
        chunkCount: (j['chunk_count'] as num?)?.toInt() ?? 0,
        assetType: j['asset_type'] as String? ?? 'file',
      );

  String get displayName {
    final parts = sourceFile.split('.');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : sourceFile;
  }

  String get ext => sourceFile.split('.').last.toUpperCase();
}

class TutorSession {
  final String sessionId;
  TutorSession(this.sessionId);
}

class TutorMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime time;

  TutorMessage({required this.role, required this.content, DateTime? time})
      : time = time ?? DateTime.now();
}

// Simple in-memory user model (no real auth yet)
class AppUser {
  final String name;
  final String email;
  final String role; // 'admin' | 'learner'
  final String initials;

  const AppUser({
    required this.name,
    required this.email,
    required this.role,
    required this.initials,
  });
}
