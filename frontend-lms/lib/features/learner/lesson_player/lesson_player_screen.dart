import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_ai_logo.dart';
import 'interactive_question.dart';
import '../../../data/providers/app_state.dart';
import '../../../data/providers/api_providers.dart';
import '../../../core/config/api_config.dart';
import '../../../core/services/course_service.dart';
import '../../../core/services/question_service.dart';
import '../../../core/services/sarvam_tts_service.dart';
import '../../../core/services/video_service.dart' show VideoRenderJob;
import '../../../data/models/lesson.dart' show CourseLesson;
import '../../../data/models/course.dart';
import '../../shared/arresto_ai/arresto_ai_panel.dart';
import '../../../core/services/progress_service.dart';

// ── Note model (persisted) ──────────────────────────────────────────────────
class _Note {
  final String id;
  int posSecs;
  String text;
  _Note({required this.id, required this.posSecs, required this.text});

  Map<String, dynamic> toJson() => {'id': id, 'pos': posSecs, 'text': text};
  factory _Note.fromJson(Map<String, dynamic> j) =>
      _Note(id: j['id'] as String, posSecs: j['pos'] as int, text: j['text'] as String);
}

// ── Transcript segments (start second, text) ────────────────────────────────
const List<(int, String)> _transcriptSegments = [
  (0, 'Welcome to this lesson. In this session we\'ll cover the key concepts you need to understand to work safely at height.'),
  (90, 'Let\'s start by looking at the regulatory requirements. According to OSHA 1926.502, all fall protection systems must meet minimum safety standards.'),
  (180, 'Anchor points must be capable of supporting at least 5,000 lbs (22 kN) per attached worker, independent of any platform support.'),
  (285, 'Always inspect your equipment before each use. Look for cuts, fraying, or corrosion that may indicate damage to webbing or hardware.'),
  (380, 'In this demonstration, notice how the inspector systematically checks each component from the D-rings down to the leg straps.'),
  (470, 'Finally, remember to calculate your total fall clearance so you never strike a lower level. That wraps up this lesson.'),
];

// ── Lesson player screen ─────────────────────────────────────────────────────
class LessonPlayerScreen extends ConsumerStatefulWidget {
  final String courseId;
  final String lessonId;
  const LessonPlayerScreen({super.key, required this.courseId, required this.lessonId});

  @override
  ConsumerState<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends ConsumerState<LessonPlayerScreen> {
  Timer? _ticker;
  Timer? _renderPollTimer;   // polls backend while renders are pending/processing
  bool _playing = false;
  int _posSecs = 0;
  int? _realVideoDurationSecs; // set once the actual video loads
  bool _showKCheck = false;
  bool _kcDone = false;
  int _xp = 120;
  int _answered = 0;
  bool _muted = false;
  String _activeTab = 'Notes';

  final _noteCtrl = TextEditingController();
  final _noteSearchCtrl = TextEditingController();
  final _transcriptSearchCtrl = TextEditingController();
  List<_Note> _notes = [];
  String? _editingNoteId;
  String _noteQuery = '';
  String _transcriptQuery = '';
  SharedPreferences? _prefs;

  // Knowledge-check questions: fetched from backend at the checkpoint
  List<InteractiveQuestion> _kcQuestions = [];
  int _kcQuestionIndex = 0;
  bool _kcLoading = false;

  // Progress tracking
  bool _startRecorded = false;
  bool _progressRecorded = false;
  int _moduleIdx = 1;
  int _lessonIdx = 1;
  String _currentLessonTitle = '';
  int _kcCorrect = 0;

  String get _notesKey => 'lesson_notes_${widget.lessonId}';

  @override
  void initState() {
    super.initState();
    // Try to restore saved position from mock data (real API doesn't store position yet)
    final mockLesson = _lesson(ref.read(lessonsProvider));
    if (mockLesson != null) _posSecs = mockLesson.savedPositionSecs;
    _track('lesson_open');
    _loadNotes();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _renderPollTimer?.cancel();
    _noteCtrl.dispose();
    _noteSearchCtrl.dispose();
    _transcriptSearchCtrl.dispose();
    super.dispose();
  }

  // ── Progress tracking ──────────────────────────────────────────────────────

  static (int, int) _parseIds(String lessonId) {
    final m = RegExp(r'm(\d+)l(\d+)').firstMatch(lessonId);
    if (m != null) return (int.parse(m.group(1)!), int.parse(m.group(2)!));
    return (1, 1);
  }

  void _initProgress(CourseLesson lesson) {
    if (_startRecorded) return;
    _startRecorded = true;
    final ids = _parseIds(lesson.id);
    _moduleIdx = ids.$1;
    _lessonIdx = ids.$2;
    _currentLessonTitle = lesson.title;
    ProgressService.recordLessonStart(
      learnerId: ref.read(learnerIdProvider),
      courseId: widget.courseId,
      moduleIdx: _moduleIdx,
      lessonIdx: _lessonIdx,
    ).catchError((_) {});
  }

  void _recordKcAttempt(InteractiveQuestion question, QuestionResult result) {
    final correctAnswer = (question.correctIndex != null &&
            question.correctIndex! < question.resolvedOptions.length)
        ? question.resolvedOptions[question.correctIndex!]
        : '';
    ProgressService.recordQuizAttempt(
      learnerId: ref.read(learnerIdProvider),
      courseId: widget.courseId,
      moduleIdx: _moduleIdx,
      lessonIdx: _lessonIdx,
      questionId: '${widget.lessonId}_kc_$_kcQuestionIndex',
      questionText: question.prompt,
      learnerAnswer: result.answer,
      correctAnswer: correctAnswer,
      isCorrect: result.correct,
      topicTag: _currentLessonTitle,
      quizType: 'lesson_checkpoint',
    ).catchError((_) {});
  }

  void _recordKcComplete() {
    if (_progressRecorded) return;
    _progressRecorded = true;
    final score = _kcQuestions.isEmpty
        ? 1.0
        : _kcCorrect / _kcQuestions.length;
    ProgressService.recordLessonComplete(
      learnerId: ref.read(learnerIdProvider),
      courseId: widget.courseId,
      moduleIdx: _moduleIdx,
      lessonIdx: _lessonIdx,
      score: score,
    ).catchError((_) {});
  }

  void _recordLessonWatched() {
    if (_progressRecorded) return;
    _progressRecorded = true;
    ProgressService.recordLessonComplete(
      learnerId: ref.read(learnerIdProvider),
      courseId: widget.courseId,
      moduleIdx: _moduleIdx,
      lessonIdx: _lessonIdx,
    ).catchError((_) {});
  }

  // ── Real video callbacks ───────────────────────────────────────────────────
  // Called by _VideoBox once the VideoPlayerController is initialised.
  void _onVideoDurationLoaded(int durationSecs) {
    if (durationSecs > 0) setState(() => _realVideoDurationSecs = durationSecs);
  }

  // Called by _VideoBox when the video reaches its end.
  void _onVideoEnded() {
    if (!mounted) return;
    final dur = _realVideoDurationSecs ?? 0;
    setState(() {
      _playing = false;
      if (dur > 0) _posSecs = dur;
    });
    _ticker?.cancel();
    _track('lesson_complete');
    _recordLessonWatched();
  }

  // ── Render-poll management ─────────────────────────────────────────────────
  void _onRendersChanged(List<VideoRenderJob>? renders) {
    final hasPending = renders?.any(
          (r) => r.status == 'pending' || r.status == 'processing') ??
        false;
    if (hasPending) {
      _renderPollTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) ref.invalidate(videoRendersProvider(widget.courseId));
      });
    } else {
      _renderPollTimer?.cancel();
      _renderPollTimer = null;
    }
  }

  // ── Analytics hook (real apps wire this to a service) ──────────────────────
  void _track(String event, [Map<String, Object?> params = const {}]) {
    debugPrint('[analytics] $event '
        'course=${widget.courseId} lesson=${widget.lessonId} t=$_posSecs $params');
  }

  // ── Notes persistence ──────────────────────────────────────────────────────
  Future<void> _loadNotes() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_notesKey);
    if (raw != null && mounted) {
      final list = (jsonDecode(raw) as List)
          .map((e) => _Note.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => _notes = list);
    }
  }

  Future<void> _persistNotes() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
        _notesKey, jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }

  CourseLesson? _lesson(List<CourseLesson> lessons) =>
      lessons.where((l) => l.id == widget.lessonId).firstOrNull;

  // ── Playback ────────────────────────────────────────────────────────────────
  void _togglePlay() {
    if ((_showKCheck || _kcLoading) && !_kcDone) return;
    setState(() => _playing = !_playing);
    _track(_playing ? 'play' : 'pause');
    if (_playing) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          // Prefer real video duration once the controller has loaded.
          final lessons = ref.read(lessonsProvider);
          final dur = _realVideoDurationSecs
              ?? _lesson(ref.read(courseLessonsProvider(widget.courseId)).valueOrNull ?? lessons)?.durationSecs
              ?? _lesson(lessons)?.durationSecs
              ?? 540;
          if (_posSecs < dur) {
            _posSecs++;
            if (!_kcDone && _posSecs == (dur * 0.25).round()) {
              _playing = false;
              _ticker?.cancel();
              _track('knowledge_check_triggered');
              _fetchAndShowKCheck();
            }
          } else {
            // Ticker reached video end (fallback when real video doesn't fire onVideoEnded)
            _playing = false;
            _ticker?.cancel();
            _track('lesson_complete');
            _recordLessonWatched();
          }
        });
      });
    } else {
      _ticker?.cancel();
    }
  }

  // ── Knowledge-check fetch + show ───────────────────────────────────────────
  Future<void> _fetchAndShowKCheck() async {
    if (!mounted) return;
    setState(() => _kcLoading = true);

    try {
      final questions = await QuestionService.generateForLesson(
        courseId:     widget.courseId,
        lessonId:     widget.lessonId,
        count:        3,
        timestampSecs: _posSecs,
      );

      if (!mounted) return;
      if (questions.isEmpty) {
        // No transcript / API key not set — skip silently and resume
        setState(() { _kcLoading = false; _kcDone = true; });
        _togglePlay();
        return;
      }
      setState(() {
        _kcLoading = false;
        _kcQuestions = questions;
        _kcQuestionIndex = 0;
        _showKCheck = true;
      });
      _track('knowledge_check_shown', {'count': questions.length});
    } catch (e) {
      debugPrint('[KCheck] fetch failed: $e');
      if (!mounted) return;
      // On error resume silently — never block the learner
      setState(() { _kcLoading = false; _kcDone = true; });
      _togglePlay();
    }
  }

  void _seekTo(int secs) {
    final lessons = ref.read(lessonsProvider);
    final dur = _lesson(lessons)?.durationSecs ?? 540;
    setState(() => _posSecs = secs.clamp(0, dur));
    _track('seek', {'to': _posSecs});
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _track('mute_toggle', {'muted': _muted});
  }

  void _onQuestionSubmit(QuestionResult result) {
    _track('knowledge_check_answered', {
      'correct': result.correct,
      'mode': result.mode.name,
      'index': _kcQuestionIndex,
    });
    _recordKcAttempt(_kcQuestions[_kcQuestionIndex], result);
    if (result.correct) {
      setState(() { _xp += 10; _answered++; _kcCorrect++; });
    }
    _advanceOrClose();
  }

  void _onQuestionSkip() {
    _track('knowledge_check_skipped', {'index': _kcQuestionIndex});
    _advanceOrClose();
  }

  void _advanceOrClose() {
    final nextIdx = _kcQuestionIndex + 1;
    if (nextIdx < _kcQuestions.length) {
      setState(() => _kcQuestionIndex = nextIdx);
    } else {
      _recordKcComplete(); // saves checkpoint score + weak topics
      setState(() {
        _kcDone = true;
        _showKCheck = false;
        _kcQuestions = [];
        _kcQuestionIndex = 0;
        _kcCorrect = 0;
      });
      _togglePlay(); // resume video after all questions done
    }
  }

  // ── Notes CRUD ──────────────────────────────────────────────────────────────
  void _saveNote() {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (_editingNoteId != null) {
        final n = _notes.firstWhere((e) => e.id == _editingNoteId);
        n.text = text;
        _editingNoteId = null;
        _track('note_edit');
      } else {
        _notes.add(_Note(
          id: '${_posSecs}_${_notes.length}_${text.hashCode}',
          posSecs: _posSecs,
          text: text,
        ));
        _track('note_create');
      }
    });
    _noteCtrl.clear();
    _persistNotes(); // auto-save
  }

  void _startEditNote(_Note n) {
    setState(() {
      _editingNoteId = n.id;
      _noteCtrl.text = n.text;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingNoteId = null;
      _noteCtrl.clear();
    });
  }

  void _deleteNote(String id) {
    setState(() => _notes.removeWhere((n) => n.id == id));
    _persistNotes();
    _track('note_delete');
  }

  void _exportNotes() {
    if (_notes.isEmpty) {
      _toast('No notes to export');
      return;
    }
    final text = _notes
        .map((n) => '[${_fmtSecs(n.posSecs)}] ${n.text}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _toast('${_notes.length} notes copied to clipboard');
    _track('notes_export');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── AI companion ────────────────────────────────────────────────────────────
  void _openAI({String? seed}) {
    final apiLessons = ref.read(courseLessonsProvider(widget.courseId)).valueOrNull;
    final lessons = (apiLessons != null && apiLessons.isNotEmpty)
        ? apiLessons
        : ref.read(lessonsProvider);
    final lesson = _lesson(lessons);
    _track('ai_open', {'seed': seed});
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ArrestoAIPanel(
        seedQuestion: seed,
        lessonContext: AiLessonContext(
          lessonId: widget.lessonId,
          courseId: widget.courseId,
          lessonTitle: lesson?.title ?? 'Lesson',
          timestampSecs: _posSecs,
          transcript: lesson?.narrationScript ?? _transcriptSegments.map((s) => s.$2).join(' '),
        ),
      ),
    );
  }

  // ── Quiz navigation with validation ──────────────────────────────────────────
  void _goToQuiz() {
    _track('go_to_quiz');
    // Validate a quiz exists for this course (mock: all courses have one).
    context.go('/learner/assessment/${widget.courseId}');
  }

  String _fmtSecs(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  int get _activeSegmentIndex {
    var idx = 0;
    for (var i = 0; i < _transcriptSegments.length; i++) {
      if (_posSecs >= _transcriptSegments[i].$1) idx = i;
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    // Use real API lessons; fall back to mock data for demo courses
    final apiLessonsAsync = ref.watch(courseLessonsProvider(widget.courseId));
    final mockLessons = ref.watch(lessonsProvider);

    if (apiLessonsAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: ArrestoColors.orange)),
      );
    }

    final apiLessons = apiLessonsAsync.valueOrNull;
    final lessons = (apiLessons != null && apiLessons.isNotEmpty)
        ? apiLessons
        : mockLessons;

    final lesson = _lesson(lessons);
    if (lesson == null) {
      return const Scaffold(body: Center(child: Text('Lesson not found')));
    }

    // Record lesson start once the lesson object is available
    WidgetsBinding.instance.addPostFrameCallback((_) => _initProgress(lesson));

    // Resolve course: try real API detail, fall back to mock list
    final courseAsync = ref.watch(courseDetailProvider(widget.courseId));
    final Course course;
    final courseDetail = courseAsync.valueOrNull;
    if (courseDetail != null && courseDetail.isNotEmpty) {
      course = CourseService.courseFromDetail(courseDetail);
    } else {
      final mockCourses = ref.watch(coursesProvider);
      course = mockCourses.firstWhere(
        (c) => c.id == widget.courseId,
        orElse: () => mockCourses.first,
      );
    }

    final dur = _realVideoDurationSecs ?? lesson.durationSecs;
    final progress = dur > 0 ? _posSecs / dur : 0.0;

    final courseLessons = lessons.where((l) => l.courseId == widget.courseId).toList();
    final lessonIndex = courseLessons.indexWhere((l) => l.id == widget.lessonId);
    final hasPrev = lessonIndex > 0;
    final hasNext = lessonIndex < courseLessons.length - 1;
    final isWide = MediaQuery.of(context).size.width > 900;

    Widget? overlay;
    if (_kcLoading) {
      overlay = const _KCheckLoadingOverlay();
    } else if (_showKCheck && _kcQuestions.isNotEmpty) {
      overlay = InteractiveQuestionOverlay(
        key: ValueKey(_kcQuestionIndex),
        question: _kcQuestions[_kcQuestionIndex],
        index:    _kcQuestionIndex + 1,
        total:    _kcQuestions.length,
        companionName: 'Arresto AI',
        onSubmit: _onQuestionSubmit,
        onSkip:   _onQuestionSkip,
      );
    }

    // Poll backend while any render is pending/processing
    ref.listen<AsyncValue<List<VideoRenderJob>>>(
      videoRendersProvider(widget.courseId),
      (_, next) => _onRendersChanged(next.valueOrNull),
    );

    // Resolve video URL and render status for this lesson
    String? videoUrl;
    String? videoRenderMessage;
    final rendersAsync = ref.watch(videoRendersProvider(widget.courseId));
    final renders = rendersAsync.valueOrNull;
    if (renders != null) {
      final ids = _parseIds(widget.lessonId);
      final standardRef = 'module_${ids.$1}_lesson_${ids.$2}';
      final customRef   = 'item_${ids.$2 - 1}'; // custom courses: item_0-based
      final lessonRenders = renders.where(
        (r) => r.lessonRef == standardRef || r.lessonRef == customRef,
      ).toList();
      final completed = lessonRenders.where((r) => r.videoReady).firstOrNull;
      if (completed != null) {
        videoUrl = '${ApiConfig.baseUrl}/api/v1/video/renders/${completed.renderId}/stream';
      } else if (lessonRenders.isNotEmpty) {
        final latest = lessonRenders.first;
        if (latest.status == 'pending' || latest.status == 'processing') {
          videoRenderMessage = 'Video is being generated — check back in a few minutes';
        } else if (latest.status == 'failed') {
          videoRenderMessage = 'Video is unavailable for this lesson.\nAn admin can re-generate it from the Admin panel.';
        }
      }
    }

    final videoBox = _VideoBox(
      lesson: lesson, posSecs: _posSecs, dur: dur, progress: progress,
      playing: _playing, muted: _muted,
      onTogglePlay: _togglePlay, fmtSecs: _fmtSecs,
      onSeekSecs: _seekTo, onToggleMute: _toggleMute,
      onNotesShortcut: () => setState(() => _activeTab = 'Notes'),
      onFullscreen: () => _toast('Fullscreen is not available in the preview build'),
      questionOverlay: overlay,
      videoUrl: videoUrl,
      renderMessage: videoRenderMessage,
      onRefreshVideo: () => ref.invalidate(videoRendersProvider(widget.courseId)),
      onDurationLoaded: _onVideoDurationLoaded,
      onVideoEnded: _onVideoEnded,
    );

    final tabsSection = _TabsSection(
      lesson: lesson,
      courseLessons: courseLessons,
      activeTab: _activeTab,
      noteCount: _notes.length,
      notes: _notes,
      noteCtrl: _noteCtrl,
      noteSearchCtrl: _noteSearchCtrl,
      transcriptSearchCtrl: _transcriptSearchCtrl,
      noteQuery: _noteQuery,
      transcriptQuery: _transcriptQuery,
      editingNoteId: _editingNoteId,
      posSecs: _posSecs,
      activeSegmentIndex: _activeSegmentIndex,
      fmtSecs: _fmtSecs,
      onTabChange: (t) => setState(() => _activeTab = t),
      onSaveNote: _saveNote,
      onStartEdit: _startEditNote,
      onCancelEdit: _cancelEdit,
      onDeleteNote: _deleteNote,
      onSeekNote: (n) => _seekTo(n.posSecs),
      onCopyNote: (n) {
        Clipboard.setData(ClipboardData(text: n.text));
        _toast('Note copied');
      },
      onExportNotes: _exportNotes,
      onAiNotes: () => _openAI(seed: 'Summarize this lesson'),
      onNoteSearch: (v) => setState(() => _noteQuery = v),
      onTranscriptSearch: (v) => setState(() => _transcriptQuery = v),
      onSeekSegment: (secs) => _seekTo(secs),
      onResourceAction: (name, download) {
        _toast(download ? 'Downloading $name…' : 'Opening $name…');
        _track(download ? 'resource_download' : 'resource_open', {'file': name});
      },
    );

    final recommendations = ref
        .watch(recommendationsProvider(widget.courseId))
        .valueOrNull ?? const [];

    final sidebar = _RightSidebar(
      lesson: lesson, course: course, courseLessons: courseLessons,
      lessonIndex: lessonIndex, lessonProgress: progress,
      xp: _xp, answered: _answered, courseProgress: course.progress / 100,
      recommendations: recommendations,
      onGoToQuiz: _goToQuiz,
      onAskAi: () => _openAI(),
      onSelectTool: (tab) => setState(() => _activeTab = tab),
    );

    return Scaffold(
      backgroundColor: ArrestoColors.background,
      body: Column(
        children: [
          Container(
            color: ArrestoColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              TextButton.icon(
                onPressed: () => context.go('/learner/course/${widget.courseId}'),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: Text(course.title, style: ArrestoText.bodyMd()),
                style: TextButton.styleFrom(foregroundColor: ArrestoColors.ink),
              ),
            ]),
          ),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${lesson.module} · Lesson ${lessonIndex + 1} of ${courseLessons.length}',
                                      style: ArrestoText.small(),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(lesson.title, style: ArrestoText.h2()),
                                  ],
                                ),
                              ),
                              videoBox,
                              _PrevNextRow(
                                onPrev: hasPrev
                                    ? () {
                                        _ticker?.cancel();
                                        context.go(
                                            '/learner/lesson/${widget.courseId}/${courseLessons[lessonIndex - 1].id}');
                                      }
                                    : null,
                                onNext: hasNext
                                    ? () {
                                        _ticker?.cancel();
                                        context.go(
                                            '/learner/lesson/${widget.courseId}/${courseLessons[lessonIndex + 1].id}');
                                      }
                                    : null,
                                onAskAi: () => _openAI(),
                              ),
                              const Divider(height: 1),
                              tabsSection,
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 300, child: sidebar),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(children: [
                      videoBox,
                      _PrevNextRow(
                        onPrev: hasPrev
                            ? () {
                                _ticker?.cancel();
                                context.go(
                                    '/learner/lesson/${widget.courseId}/${courseLessons[lessonIndex - 1].id}');
                              }
                            : null,
                        onNext: hasNext
                            ? () {
                                _ticker?.cancel();
                                context.go(
                                    '/learner/lesson/${widget.courseId}/${courseLessons[lessonIndex + 1].id}');
                              }
                            : null,
                        onAskAi: () => _openAI(),
                      ),
                      const Divider(height: 1),
                      tabsSection,
                      sidebar,
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Prev / Next / Ask AI row ──────────────────────────────────────────────────
class _PrevNextRow extends StatelessWidget {
  final VoidCallback? onPrev, onNext;
  final VoidCallback onAskAi;
  const _PrevNextRow({required this.onPrev, required this.onNext, required this.onAskAi});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        ArrestoButton(
          label: 'Prev',
          variant: ArrestoButtonVariant.ghost,
          size: ArrestoButtonSize.sm,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onPrev,
        ),
        const Spacer(),
        ArrestoButton(
          label: 'Next lesson',
          size: ArrestoButtonSize.sm,
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: onNext,
        ),
        const SizedBox(width: 12),
        ArrestoButton(
          label: 'Ask Arresto AI',
          variant: ArrestoButtonVariant.ghost,
          size: ArrestoButtonSize.sm,
          icon: const ArrestoAiLogo(size: 18),
          onPressed: onAskAi,
        ),
      ]),
    );
  }
}

// ── Video box ─────────────────────────────────────────────────────────────────
// Shows the actual HeyGen-rendered MP4 when [videoUrl] is provided; falls back
// to the simulated dark-gradient player when no render is available yet.
class _VideoBox extends StatefulWidget {
  final CourseLesson lesson;
  final int posSecs, dur;
  final double progress;
  final bool playing, muted;
  final VoidCallback onTogglePlay, onToggleMute, onNotesShortcut, onFullscreen;
  final Function(int) onSeekSecs;
  final String Function(int) fmtSecs;
  final Widget? questionOverlay;
  final String? videoUrl;
  final String? renderMessage;
  final VoidCallback? onRefreshVideo;
  final void Function(int durationSecs)? onDurationLoaded;
  final VoidCallback? onVideoEnded;

  const _VideoBox({
    required this.lesson, required this.posSecs, required this.dur,
    required this.progress, required this.playing, required this.muted,
    required this.onTogglePlay, required this.fmtSecs,
    required this.onSeekSecs, required this.onToggleMute,
    required this.onNotesShortcut, required this.onFullscreen,
    this.questionOverlay,
    this.videoUrl,
    this.renderMessage,
    this.onRefreshVideo,
    this.onDurationLoaded,
    this.onVideoEnded,
  });

  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  VideoPlayerController? _vc;
  bool _vcReady = false;
  bool _videoEnded = false;
  String? _loadedUrl;

  @override
  void initState() {
    super.initState();
    if (widget.videoUrl != null) _initVideo(widget.videoUrl!);
  }

  @override
  void didUpdateWidget(_VideoBox old) {
    super.didUpdateWidget(old);
    // Load (or reload) if the URL first appears or changes
    if (widget.videoUrl != null && widget.videoUrl != _loadedUrl) {
      _initVideo(widget.videoUrl!);
      return;
    }
    if (_vc == null || !_vcReady) return;

    // Sync play / pause
    if (widget.playing != old.playing) {
      widget.playing ? _vc!.play() : _vc!.pause();
    }
    // Sync mute
    if (widget.muted != old.muted) {
      _vc!.setVolume(widget.muted ? 0.0 : 1.0);
    }
    // Sync seek when parent position drifts > 3 s from the real video position
    if (widget.posSecs != old.posSecs) {
      final ctrlSecs = _vc!.value.position.inSeconds;
      if ((ctrlSecs - widget.posSecs).abs() > 3) {
        _vc!.seekTo(Duration(seconds: widget.posSecs));
      }
    }
  }

  Future<void> _initVideo(String url) async {
    _loadedUrl = url;
    _videoEnded = false;
    final vc = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await vc.initialize();
      if (!mounted) { vc.dispose(); return; }
      final old = _vc;
      _vc = vc;
      _vcReady = true;
      // Report real duration to the parent so it can replace the mock value
      final realDur = vc.value.duration.inSeconds;
      if (realDur > 0) widget.onDurationLoaded?.call(realDur);
      // Listen for video reaching its natural end
      vc.addListener(_onControllerUpdate);
      if (widget.playing) vc.play();
      vc.setVolume(widget.muted ? 0.0 : 1.0);
      setState(() {});
      old?.dispose();
    } catch (e) {
      debugPrint('[VideoBox] init failed: $e');
      vc.dispose();
    }
  }

  void _onControllerUpdate() {
    if (_videoEnded || _vc == null || !_vcReady) return;
    final val = _vc!.value;
    if (!val.isInitialized || val.duration.inMilliseconds == 0) return;
    if (val.position >= val.duration && !val.isPlaying) {
      _videoEnded = true;
      widget.onVideoEnded?.call();
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xFF111111),
        child: Stack(
          children: [
            // ── Background: real video or gradient fallback ──────────────────
            if (_vcReady && _vc != null)
              Positioned.fill(child: VideoPlayer(_vc!))
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1a1a1a), Color(0xFF0d0d0d)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: widget.videoUrl == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.renderMessage != null && widget.renderMessage!.contains('failed')
                                  ? Icons.error_outline_rounded
                                  : widget.renderMessage != null
                                      ? Icons.hourglass_top_rounded
                                      : Icons.videocam_off_rounded,
                              color: Colors.white30,
                              size: 40,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.renderMessage ?? 'Video not yet generated for this lesson',
                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.onRefreshVideo != null) ...[
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: widget.onRefreshVideo,
                                icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white38),
                                label: const Text('Refresh', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      )
                    : null,
              ),

            // Loading spinner while video initialises
            if (widget.videoUrl != null && !_vcReady)
              const Center(child: CircularProgressIndicator(color: ArrestoColors.amber, strokeWidth: 3)),

            // Play button (centre) when paused and no overlay
            if (!widget.playing && widget.questionOverlay == null)
              Center(
                child: GestureDetector(
                  onTap: widget.onTogglePlay,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: ArrestoColors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: ArrestoColors.amber.withValues(alpha: 0.4), blurRadius: 24)],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: ArrestoColors.ink, size: 40),
                  ),
                ),
              ),

            // Pause button (top-right) when playing
            if (widget.playing)
              Positioned(
                right: 16, top: 16,
                child: GestureDetector(
                  onTap: widget.onTogglePlay,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.pause_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),

            // Controls bar
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                child: Column(children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: ArrestoColors.amber,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: ArrestoColors.amber,
                      overlayColor: ArrestoColors.amber.withValues(alpha: 0.3),
                    ),
                    child: Slider(
                      value: widget.progress.clamp(0.0, 1.0),
                      onChanged: (v) => widget.onSeekSecs((v * widget.dur).round()),
                    ),
                  ),
                  Row(children: [
                    _ctrl(Icons.replay_10_rounded, () => widget.onSeekSecs(widget.posSecs - 10)),
                    _ctrl(widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, widget.onTogglePlay),
                    _ctrl(Icons.forward_10_rounded, () => widget.onSeekSecs(widget.posSecs + 10)),
                    _ctrl(widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, widget.onToggleMute),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.fmtSecs(widget.posSecs)} / ${widget.fmtSecs(widget.dur)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    _pill('1×'),
                    const SizedBox(width: 6),
                    _pill('CC'),
                    const SizedBox(width: 6),
                    _ctrl(Icons.note_alt_outlined, widget.onNotesShortcut),
                    _ctrl(Icons.fullscreen_rounded, widget.onFullscreen),
                  ]),
                ]),
              ),
            ),

            if (widget.questionOverlay != null) widget.questionOverlay!,
          ],
        ),
      ),
    );
  }

  Widget _ctrl(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: Colors.white70, size: 20),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );

  Widget _pill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

// ── Tabs section (shared by both layouts) ─────────────────────────────────────
class _TabsSection extends StatelessWidget {
  final CourseLesson lesson;
  final List<CourseLesson> courseLessons;
  final String activeTab;
  final int noteCount, posSecs, activeSegmentIndex;
  final List<_Note> notes;
  final TextEditingController noteCtrl, noteSearchCtrl, transcriptSearchCtrl;
  final String noteQuery, transcriptQuery;
  final String? editingNoteId;
  final String Function(int) fmtSecs;
  final Function(String) onTabChange;
  final VoidCallback onSaveNote, onCancelEdit, onExportNotes, onAiNotes;
  final Function(_Note) onStartEdit, onSeekNote, onCopyNote;
  final Function(String) onDeleteNote, onNoteSearch, onTranscriptSearch;
  final Function(int) onSeekSegment;
  final void Function(String name, bool download) onResourceAction;

  const _TabsSection({
    required this.lesson, required this.courseLessons, required this.activeTab,
    required this.noteCount, required this.posSecs, required this.activeSegmentIndex,
    required this.notes, required this.noteCtrl, required this.noteSearchCtrl,
    required this.transcriptSearchCtrl, required this.noteQuery, required this.transcriptQuery,
    required this.editingNoteId, required this.fmtSecs, required this.onTabChange,
    required this.onSaveNote, required this.onCancelEdit, required this.onExportNotes,
    required this.onAiNotes, required this.onStartEdit, required this.onSeekNote,
    required this.onCopyNote, required this.onDeleteNote, required this.onNoteSearch,
    required this.onTranscriptSearch, required this.onSeekSegment, required this.onResourceAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TabBar(activeTab: activeTab, noteCount: noteCount, onTabChange: onTabChange),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(20),
        child: activeTab == 'Notes'
            ? _NotesTab(
                notes: notes, noteCtrl: noteCtrl, noteSearchCtrl: noteSearchCtrl,
                noteQuery: noteQuery, editingNoteId: editingNoteId, fmtSecs: fmtSecs,
                onSave: onSaveNote, onCancelEdit: onCancelEdit, onExport: onExportNotes,
                onAiNotes: onAiNotes, onStartEdit: onStartEdit, onSeek: onSeekNote,
                onCopy: onCopyNote, onDelete: onDeleteNote, onSearch: onNoteSearch,
              )
            : activeTab == 'Resources'
                ? _ResourcesTab(onAction: onResourceAction)
                : _TranscriptTab(
                    lesson: lesson, posSecs: posSecs, activeIndex: activeSegmentIndex,
                    searchCtrl: transcriptSearchCtrl, query: transcriptQuery,
                    fmtSecs: fmtSecs, onSearch: onTranscriptSearch, onSeek: onSeekSegment,
                  ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.grid_view_rounded, size: 18, color: ArrestoColors.orange),
            const SizedBox(width: 8),
            Text('Related lessons', style: ArrestoText.h3()),
          ]),
          const SizedBox(height: 4),
          Text('In this course', style: ArrestoText.small()),
          const SizedBox(height: 12),
          ...courseLessons.where((l) => l.id != lesson.id).take(3).map((l) => _RelatedLessonRow(lesson: l)),
        ]),
      ),
    ]);
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final String activeTab;
  final int noteCount;
  final Function(String) onTabChange;
  const _TabBar({required this.activeTab, required this.noteCount, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['Notes', 'Resources', 'Transcript'].map((tab) {
        final active = tab == activeTab;
        return GestureDetector(
          onTap: () => onTabChange(tab),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? ArrestoColors.orange : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tab, style: active ? ArrestoText.bodyBold(color: ArrestoColors.orange) : ArrestoText.body()),
              if (tab == 'Notes' && noteCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: ArrestoColors.orange, borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('$noteCount', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ── Notes tab ─────────────────────────────────────────────────────────────────
class _NotesTab extends StatelessWidget {
  final List<_Note> notes;
  final TextEditingController noteCtrl, noteSearchCtrl;
  final String noteQuery;
  final String? editingNoteId;
  final String Function(int) fmtSecs;
  final VoidCallback onSave, onCancelEdit, onExport, onAiNotes;
  final Function(_Note) onStartEdit, onSeek, onCopy;
  final Function(String) onDelete, onSearch;

  const _NotesTab({
    required this.notes, required this.noteCtrl, required this.noteSearchCtrl,
    required this.noteQuery, required this.editingNoteId, required this.fmtSecs,
    required this.onSave, required this.onCancelEdit, required this.onExport,
    required this.onAiNotes, required this.onStartEdit, required this.onSeek,
    required this.onCopy, required this.onDelete, required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final editing = editingNoteId != null;
    final filtered = noteQuery.isEmpty
        ? notes
        : notes.where((n) => n.text.toLowerCase().contains(noteQuery.toLowerCase())).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: noteCtrl,
            minLines: 2,
            maxLines: 4,
            onSubmitted: (_) => onSave(),
            decoration: InputDecoration(
              hintText: editing ? 'Edit note…' : 'Write a note at this timestamp…',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(children: [
          ArrestoButton(label: editing ? 'Save' : 'Add note', size: ArrestoButtonSize.sm, onPressed: onSave),
          if (editing) ...[
            const SizedBox(height: 6),
            TextButton(onPressed: onCancelEdit, child: const Text('Cancel')),
          ],
        ]),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        ArrestoButton(
          label: 'Arresto AI notes',
          size: ArrestoButtonSize.sm,
          variant: ArrestoButtonVariant.ghost,
          icon: const ArrestoAiLogo(size: 18),
          onPressed: onAiNotes,
        ),
        const SizedBox(width: 8),
        ArrestoButton(
          label: 'Export',
          size: ArrestoButtonSize.sm,
          variant: ArrestoButtonVariant.ghost,
          icon: const Icon(Icons.download_rounded),
          onPressed: onExport,
        ),
      ]),
      const SizedBox(height: 12),
      if (notes.isNotEmpty)
        TextField(
          controller: noteSearchCtrl,
          onChanged: onSearch,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Search notes…',
          ),
        ),
      const SizedBox(height: 12),
      if (notes.isEmpty)
        Text('No notes yet. Add a note above — it\'s tagged to the current video time and saved automatically.',
            style: ArrestoText.small())
      else if (filtered.isEmpty)
        Text('No notes match "$noteQuery".', style: ArrestoText.small()),
      ...filtered.map((n) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ArrestoColors.amberSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ArrestoColors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => onSeek(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: ArrestoColors.amber, borderRadius: BorderRadius.circular(6)),
                  child: Text(fmtSecs(n.posSecs), style: ArrestoText.xs()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(n.text, style: ArrestoText.body())),
              Row(children: [
                _iconBtn(Icons.copy_rounded, () => onCopy(n)),
                _iconBtn(Icons.edit_rounded, () => onStartEdit(n)),
                _iconBtn(Icons.delete_outline_rounded, () => onDelete(n.id)),
              ]),
            ]),
          )),
    ]);
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, size: 15, color: ArrestoColors.textMuted),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      );
}

// ── Resources tab ─────────────────────────────────────────────────────────────
class _ResourcesTab extends StatelessWidget {
  final void Function(String name, bool download) onAction;
  const _ResourcesTab({required this.onAction});

  static const _res = [
    ('Fall Protection Checklist.pdf', 'PDF', '1.2 MB'),
    ('Anchor Point Rating Chart.pdf', 'PDF', '0.8 MB'),
    ('OHSMS Compliance Matrix.xlsx', 'XLS', '2.1 MB'),
  ];

  @override
  Widget build(BuildContext context) {
    if (_res.isEmpty) {
      return Text('No resources attached to this lesson.', style: ArrestoText.small());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _res.map((r) {
        final isPdf = r.$2 == 'PDF';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ArrestoColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ArrestoColors.line),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPdf ? ArrestoColors.redSoft : ArrestoColors.greenSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.description_rounded, size: 18, color: isPdf ? ArrestoColors.red : ArrestoColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.$1, style: ArrestoText.bodyBold()),
                Text('${r.$2} · ${r.$3}', style: ArrestoText.xs()),
              ]),
            ),
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new_rounded, color: ArrestoColors.textMuted, size: 20),
              onPressed: () => onAction(r.$1, false),
            ),
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded, color: ArrestoColors.orange),
              onPressed: () => onAction(r.$1, true),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ── Transcript tab ────────────────────────────────────────────────────────────
class _TranscriptTab extends StatefulWidget {
  final CourseLesson lesson;
  final int posSecs, activeIndex;
  final TextEditingController searchCtrl;
  final String query;
  final String Function(int) fmtSecs;
  final Function(String) onSearch;
  final Function(int) onSeek;

  const _TranscriptTab({
    required this.lesson, required this.posSecs, required this.activeIndex,
    required this.searchCtrl, required this.query, required this.fmtSecs,
    required this.onSearch, required this.onSeek,
  });

  @override
  State<_TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends State<_TranscriptTab> {
  final _tts = SarvamTtsPlayer();

  @override
  void initState() {
    super.initState();
    _tts.onStateChange = () { if (mounted) setState(() {}); };
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  String? get _scriptText {
    final script = widget.lesson.narrationScript;
    if (script == null || script.isEmpty) return null;
    return script;
  }

  void _toggleSpeak() {
    final text = _scriptText;
    if (text == null) return;
    if (_tts.isSpeaking) {
      _tts.pause();
    } else if (_tts.isPaused) {
      _tts.resume();
    } else {
      _tts.speak(text).catchError((e) => debugPrint('[TTS] $e'));
    }
  }

  void _stopSpeak() => _tts.stop();

  Widget _chip(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (color ?? ArrestoColors.orange).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: (color ?? ArrestoColors.orange).withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color ?? ArrestoColors.orange),
          const SizedBox(width: 5),
          Text(label,
              style: ArrestoText.xs(color: color ?? ArrestoColors.orange)
                  .copyWith(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query.toLowerCase();
    final hasRealScript = widget.lesson.narrationScript?.isNotEmpty == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with TTS controls
        Row(children: [
          Expanded(
            child: Text('Transcript — ${widget.lesson.title}',
                style: ArrestoText.bodyBold()),
          ),
          const SizedBox(width: 8),
          if (_scriptText == null)
            // No narration script available — show muted hint
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.volume_off_rounded,
                  size: 14, color: ArrestoColors.textMuted),
              const SizedBox(width: 4),
              Text('No audio script',
                  style: ArrestoText.xs(color: ArrestoColors.textMuted)),
            ])
          else if (!_tts.isActive)
            _chip(Icons.volume_up_rounded, 'Listen', _toggleSpeak)
          else ...[
            _chip(
              _tts.isLoading
                  ? Icons.hourglass_empty_rounded
                  : _tts.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
              _tts.isLoading ? 'Loading…' : _tts.isPaused ? 'Resume' : 'Pause',
              _tts.isLoading ? () {} : _toggleSpeak,
            ),
            const SizedBox(width: 6),
            _chip(Icons.stop_rounded, 'Stop', _stopSpeak,
                color: ArrestoColors.textSecondary),
          ],
        ]),

        if (_tts.isSpeaking)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.volume_up_rounded, size: 13, color: ArrestoColors.orange),
              const SizedBox(width: 5),
              Text('Playing narration…',
                  style: ArrestoText.xs(color: ArrestoColors.orange)),
            ]),
          ),

        const SizedBox(height: 10),
        TextField(
          controller: widget.searchCtrl,
          onChanged: widget.onSearch,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Search transcript…',
          ),
        ),
        const SizedBox(height: 12),

        // Real narration script (full text block)
        if (hasRealScript) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _tts.isSpeaking ? ArrestoColors.amberSoft : ArrestoColors.bg2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _tts.isSpeaking
                    ? ArrestoColors.amber.withValues(alpha: 0.5)
                    : ArrestoColors.cardBorder,
              ),
            ),
            child: SelectableText(
              q.isEmpty
                  ? widget.lesson.narrationScript!
                  : (widget.lesson.narrationScript!.toLowerCase().contains(q)
                      ? widget.lesson.narrationScript!
                      : '(No matches for "$q")'),
              style: ArrestoText.body(color: ArrestoColors.ink),
            ),
          ),
        ] else ...[
          // No script available placeholder
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ArrestoColors.bg2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ArrestoColors.cardBorder),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: ArrestoColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Transcript not available for this lesson.',
                  style: ArrestoText.small(color: ArrestoColors.textMuted),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // Timed mock segments (kept only as placeholder structure)
          ...List.generate(_transcriptSegments.length, (i) {
            final seg = _transcriptSegments[i];
            if (q.isNotEmpty && !seg.$2.toLowerCase().contains(q)) {
              return const SizedBox.shrink();
            }
            final isActive = i == widget.activeIndex;
            return InkWell(
              onTap: () => widget.onSeek(seg.$1),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? ArrestoColors.amberSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? ArrestoColors.amber.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 40,
                    child: Text(widget.fmtSecs(seg.$1),
                        style: ArrestoText.xs(
                            color: isActive
                                ? ArrestoColors.orange
                                : ArrestoColors.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(seg.$2,
                        style: isActive
                            ? ArrestoText.body(color: ArrestoColors.ink)
                                .copyWith(fontWeight: FontWeight.w600)
                            : ArrestoText.body()),
                  ),
                  if (isActive)
                    const Icon(Icons.volume_up_rounded,
                        size: 14, color: ArrestoColors.orange),
                ]),
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ── Related lesson row ────────────────────────────────────────────────────────
class _RelatedLessonRow extends StatelessWidget {
  final CourseLesson lesson;
  const _RelatedLessonRow({required this.lesson});

  static const _icons = [
    Icons.grid_view_rounded,
    Icons.edit_rounded,
    Icons.layers_rounded,
    Icons.auto_awesome_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final icon = _icons[lesson.id.hashCode % _icons.length];
    return InkWell(
      onTap: () => context.go('/learner/lesson/${lesson.courseId}/${lesson.id}'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ArrestoColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ArrestoColors.line),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: ArrestoColors.amberSoft, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: ArrestoColors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lesson.title, style: ArrestoText.bodyBold(), overflow: TextOverflow.ellipsis),
              Text('${lesson.module} · ${lesson.durationSecs ~/ 60} min', style: ArrestoText.xs()),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: ArrestoColors.textMuted),
        ]),
      ),
    );
  }
}

// ── Knowledge-check loading overlay ──────────────────────────────────────────
class _KCheckLoadingOverlay extends StatelessWidget {
  const _KCheckLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: ArrestoColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: ArrestoColors.amber, strokeWidth: 3),
              const SizedBox(height: 14),
              Text('Generating knowledge check…', style: ArrestoText.bodyBold()),
              const SizedBox(height: 4),
              Text('Arresto AI is reading the lesson',
                  style: ArrestoText.small(color: ArrestoColors.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Right sidebar ─────────────────────────────────────────────────────────────
class _RightSidebar extends StatelessWidget {
  final CourseLesson lesson;
  final Course course;
  final List<CourseLesson> courseLessons;
  final int lessonIndex;
  final double lessonProgress, courseProgress;
  final int xp, answered;
  final List<Recommendation> recommendations;
  final VoidCallback onGoToQuiz, onAskAi;
  final Function(String) onSelectTool;

  const _RightSidebar({
    required this.lesson, required this.course, required this.courseLessons,
    required this.lessonIndex, required this.lessonProgress, required this.courseProgress,
    required this.xp, required this.answered, required this.recommendations,
    required this.onGoToQuiz, required this.onAskAi, required this.onSelectTool,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ArrestoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const ArrestoAiLogo(size: 34),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Learning companion', style: ArrestoText.bodyBold()),
                Text('Powered by Arresto AI', style: ArrestoText.xs()),
              ]),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.play_arrow_rounded, size: 14, color: ArrestoColors.orange),
              const SizedBox(width: 4),
              Text('NOW PLAYING', style: ArrestoText.eyebrow()),
            ]),
            Text(lesson.title, style: ArrestoText.bodyBold(), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            _progressRow('Lesson progress', lessonProgress, ArrestoColors.amber),
            const SizedBox(height: 8),
            _progressRow('Knowledge score', 1.0, ArrestoColors.green),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Column(children: [
                Text('$answered', style: ArrestoText.stat()),
                Text('Answered', style: ArrestoText.xs()),
              ])),
              Expanded(child: Column(children: [
                Text('$xp', style: ArrestoText.stat().copyWith(color: ArrestoColors.orange)),
                Text('XP', style: ArrestoText.xs()),
              ])),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ArrestoButton(
                label: 'Ask Arresto AI',
                variant: ArrestoButtonVariant.dark,
                icon: const ArrestoAiLogo(size: 18),
                onPressed: onAskAi,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        ArrestoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quick tools', style: ArrestoText.bodyBold()),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _quickTool(Icons.note_rounded, 'Notes', onTap: () => onSelectTool('Notes'))),
              const SizedBox(width: 8),
              Expanded(child: _quickTool(Icons.description_rounded, 'Resources', onTap: () => onSelectTool('Resources'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _quickTool(Icons.text_snippet_rounded, 'Transcript', onTap: () => onSelectTool('Transcript'))),
              const SizedBox(width: 8),
              Expanded(child: _quickTool(Icons.quiz_rounded, 'Go to quiz', onTap: onGoToQuiz)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        ArrestoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Course progress', style: ArrestoText.bodyBold()),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: courseProgress,
                  backgroundColor: ArrestoColors.amberSoft,
                  valueColor: const AlwaysStoppedAnimation(ArrestoColors.amber),
                  minHeight: 6,
                ),
              )),
              const SizedBox(width: 8),
              Text('${(courseProgress * 100).round()}%', style: ArrestoText.smallBold()),
            ]),
            Text('${(courseProgress * 100).round()}% complete · ${courseLessons.length} lessons', style: ArrestoText.xs()),
            const SizedBox(height: 12),
            ...courseLessons.take(8).map((l) {
              final isActive = l.id == lesson.id;
              return InkWell(
                onTap: () => context.go('/learner/lesson/${l.courseId}/${l.id}'),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(
                      l.completed ? Icons.check_circle_rounded : (isActive ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                      size: 16,
                      color: l.completed ? ArrestoColors.green : (isActive ? ArrestoColors.orange : ArrestoColors.textMuted2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      l.title,
                      style: isActive
                          ? ArrestoText.bodyBold(color: ArrestoColors.orange)
                          : ArrestoText.body(color: l.completed ? ArrestoColors.textSecondary : ArrestoColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ),
              );
            }),
          ]),
        ),
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 14),
          ArrestoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.flag_rounded, size: 16, color: ArrestoColors.orange),
                  const SizedBox(width: 8),
                  Text('Focus areas', style: ArrestoText.bodyBold()),
                ]),
                const SizedBox(height: 10),
                ...recommendations.take(4).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        r.type == 'weak_topic'
                            ? Icons.warning_amber_rounded
                            : Icons.replay_rounded,
                        size: 14,
                        color: ArrestoColors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.message, style: ArrestoText.small()),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _progressRow(String label, double value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: ArrestoText.small()),
        const Spacer(),
        Text('${(value * 100).round()}%', style: ArrestoText.smallBold()),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: color.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 6,
        ),
      ),
    ]);
  }

  Widget _quickTool(IconData icon, String label, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: ArrestoColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: ArrestoColors.orange),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: ArrestoText.small(), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
