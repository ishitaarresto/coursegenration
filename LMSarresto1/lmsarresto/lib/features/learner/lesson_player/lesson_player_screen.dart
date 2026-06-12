import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/colors.dart';
import '../../../core/api/course_service.dart';
import '../../../core/api/audio_service.dart';
import '../../../core/api/video_service.dart';
import '../../../core/api/tutor_service.dart';
import '../../../core/api/models.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_card.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'quiz_widgets.dart';

enum _Phase { lesson, quiz, structuredQuiz, score, done }

// ─────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────
class LessonPlayerScreen extends ConsumerStatefulWidget {
  const LessonPlayerScreen({super.key, required this.scriptId, required this.lessonRef});
  final String scriptId;
  final String lessonRef;
  @override
  ConsumerState<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends ConsumerState<LessonPlayerScreen> {
  CourseScript? _script;
  CourseModule? _module;
  CourseLesson? _lesson;
  bool _loading = true;
  String? _error;
  late int _moduleNumber;
  late int _lessonNumber;
  String? _sessionId;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    final parts = widget.lessonRef.split('_');
    _moduleNumber = int.tryParse(parts.isNotEmpty ? parts[0].replaceAll('m', '') : '1') ?? 1;
    _lessonNumber = int.tryParse(parts.length > 1 ? parts[1].replaceAll('l', '') : '1') ?? 1;
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final script = await CourseService.getScript(widget.scriptId);
      CourseModule? mod;
      CourseLesson? lesson;
      for (final m in script.modules) {
        if (m.moduleNumber == _moduleNumber) {
          mod = m;
          for (final l in m.lessons) {
            if (l.lessonNumber == _lessonNumber) { lesson = l; break; }
          }
          break;
        }
      }
      if (mounted) setState(() { _script = script; _module = mod; _lesson = lesson; _loading = false; });
      _initTutor();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _initTutor() async {
    final auth = ref.read(authProvider);
    try {
      final result = await TutorService.createSession(
        scriptId: widget.scriptId,
        learnerId: auth.user?.email ?? 'learner',
        currentModule: _moduleNumber,
        currentLesson: _lessonNumber,
      );
      if (mounted) setState(() => _sessionId = result['session_id'] as String?);
    } catch (e) {
      if (mounted) setState(() => _sessionError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: _LessonContent(
            scriptId: widget.scriptId,
            module: _module,
            lesson: _lesson,
            moduleNumber: _moduleNumber,
            lessonNumber: _lessonNumber,
            sessionId: _sessionId,
          ),
        ),
        const SizedBox(width: 20),
        SizedBox(width: 320, child: _TutorPanel(sessionId: _sessionId, sessionError: _sessionError)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Lesson Content Panel
// ─────────────────────────────────────────────────────────────────
class _LessonContent extends StatefulWidget {
  const _LessonContent({
    required this.scriptId, required this.module, required this.lesson,
    required this.moduleNumber, required this.lessonNumber, required this.sessionId,
  });
  final String scriptId;
  final CourseModule? module;
  final CourseLesson? lesson;
  final int moduleNumber;
  final int lessonNumber;
  final String? sessionId;
  @override
  State<_LessonContent> createState() => _LessonContentState();
}

class _LessonContentState extends State<_LessonContent> {
  // Audio
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _audioLoading = false;
  bool _audioError = false;
  final List<StreamSubscription> _subs = [];

  // Video
  VideoRender? _videoRender;

  // Quiz
  _Phase _phase = _Phase.lesson;
  List<Map<String, dynamic>> _questions = [];
  int _currentQ = 0;
  final _answerCtrl = TextEditingController();
  bool _submitted = false;
  Map<String, dynamic>? _answerResult;
  String? _selectedOption;
  int _correctCount = 0;
  bool _processingAction = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _playerState = s); }));
    _subs.add(_player.onPositionChanged.listen((d) { if (mounted) setState(() => _position = d); }));
    _subs.add(_player.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); }));
    _loadExistingVideo();
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingVideo() async {
    try {
      final renders = await VideoService.getScriptRenders(widget.scriptId);
      final ref = 'm${widget.moduleNumber}_l${widget.lessonNumber}';
      final match = renders.where((r) =>
          r.videoReady && (r.lessonRef == ref || r.lessonRef.contains(ref))).toList();
      if (match.isNotEmpty && mounted) setState(() => _videoRender = match.last);
    } catch (_) {}
  }

  Future<void> _playAudio() async {
    if (_audioLoading) return;
    setState(() { _audioLoading = true; _audioError = false; });
    try {
      final url = AudioService.lessonAudioUrl(widget.scriptId, widget.moduleNumber, widget.lessonNumber);
      await _player.play(UrlSource(url));
    } catch (_) {
      if (mounted) setState(() => _audioError = true);
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else if (_playerState == PlayerState.paused) {
      await _player.resume();
    } else {
      await _playAudio();
    }
  }

  Future<void> _completeLesson() async {
    // If the lesson has embedded structured questions, use them directly.
    final embedded = widget.lesson?.quizQuestions ?? [];
    if (embedded.isNotEmpty) {
      setState(() { _questions = embedded; _currentQ = 0; _phase = _Phase.structuredQuiz; });
      return;
    }

    if (widget.sessionId == null) return;
    setState(() { _processingAction = true; _actionError = null; });
    try {
      final result = await TutorService.completeLesson(widget.sessionId!);
      final questions = (result['questions'] as List? ?? [])
          .map((q) => q as Map<String, dynamic>).toList();
      if (mounted) setState(() {
        _questions = questions;
        _currentQ = 0;
        _correctCount = 0;
        _phase = _Phase.quiz;
        _processingAction = false;
      });
    } catch (e) {
      if (mounted) setState(() { _actionError = e.toString(); _processingAction = false; });
    }
  }

  Future<void> _submitAnswer([String? optionKey]) async {
    final answer = optionKey ?? _answerCtrl.text.trim();
    if (answer.isEmpty || widget.sessionId == null) return;
    if (optionKey != null) setState(() => _selectedOption = optionKey);
    setState(() { _submitted = true; _processingAction = true; });
    final q = _questions[_currentQ];
    try {
      final result = await TutorService.submitAnswer(
          widget.sessionId!, q['question_id'] as String, answer);
      if (mounted) {
        if (result['correct'] == true) _correctCount++;
        setState(() { _answerResult = result; _processingAction = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _processingAction = false; });
    }
  }

  void _nextQuestion() {
    _answerCtrl.clear();
    if (_currentQ + 1 < _questions.length) {
      setState(() { _currentQ++; _submitted = false; _answerResult = null; _selectedOption = null; });
    } else {
      setState(() => _phase = _Phase.score);
    }
  }

  Future<void> _goNextLesson() async {
    if (widget.sessionId == null) return;
    setState(() { _processingAction = true; _actionError = null; });
    try {
      final result = await TutorService.nextLesson(widget.sessionId!);
      final action = result['action'] as String? ?? '';
      final nextMod = result['current_module'] as int? ?? widget.moduleNumber;
      final nextLes = result['current_lesson'] as int? ?? widget.lessonNumber;
      if (!mounted) return;
      if (action == 'course_complete') {
        setState(() { _phase = _Phase.done; _processingAction = false; });
      } else {
        context.go('/learner/lesson/${widget.scriptId}/m${nextMod}_l$nextLes');
      }
    } catch (e) {
      if (mounted) setState(() { _actionError = e.toString(); _processingAction = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.lesson          => _buildLesson(),
      _Phase.quiz            => _buildQuiz(),
      _Phase.structuredQuiz  => _buildStructuredQuiz(),
      _Phase.score           => _buildScore(),
      _Phase.done            => _buildDone(),
    };
  }

  Widget _buildLesson() {
    final lesson = widget.lesson;
    final module = widget.module;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (module != null)
          Text('Module ${module.moduleNumber}: ${module.title}',
              style: const TextStyle(fontSize: 12, color: AColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(lesson?.title ?? 'Lesson ${widget.lessonNumber}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AColors.ink)),
        const SizedBox(height: 20),

        // Audio player
        ACard(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            GestureDetector(
              onTap: _audioLoading ? null : _togglePlay,
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
                child: _audioLoading
                    ? const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AColors.ink)))
                    : Icon(_playerState == PlayerState.playing
                        ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: AColors.ink, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lesson Narration',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AColors.ink)),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderThemeData(
                  thumbColor: AColors.amber,
                  activeTrackColor: AColors.amber,
                  inactiveTrackColor: AColors.bg2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble())
                      : 0,
                  max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                  onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_fmt(_position), style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
                Text(_fmt(_duration), style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
              ]),
            ])),
          ]),
        ),
        if (_audioError)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Audio not available — narration may not have been generated yet.',
                style: TextStyle(fontSize: 12, color: AColors.textMuted)),
          ),
        const SizedBox(height: 12),

        // Video player (if rendered)
        if (_videoRender != null)
          _VideoCard(render: _videoRender!),

        const SizedBox(height: 16),

        // Narration script
        if (lesson != null && lesson.narrationScript.isNotEmpty)
          APanel(
            title: 'Narration Script',
            child: Text(lesson.narrationScript,
                style: const TextStyle(fontSize: 14, color: AColors.textSecond, height: 1.7)),
          ),

        // Slide content
        if (lesson != null && lesson.slides.isNotEmpty) ...[
          const SizedBox(height: 16),
          APanel(
            title: 'Slide Content',
            child: Column(children: lesson.slides.map((s) => _SlideCard(s)).toList()),
          ),
        ],

        const SizedBox(height: 24),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_actionError!, style: const TextStyle(fontSize: 12, color: AColors.red)),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AButton(
            label: 'Mark as Complete',
            icon: Icons.check_circle_outline_rounded,
            loading: _processingAction,
            onPressed: widget.sessionId == null || _processingAction ? null : _completeLesson,
          ),
        ]),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildQuiz() {
    if (_questions.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, size: 64, color: AColors.green),
        const SizedBox(height: 16),
        const Text('Lesson complete!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AColors.ink)),
        const SizedBox(height: 24),
        AButton(label: 'Next Lesson', icon: Icons.arrow_forward_rounded,
            loading: _processingAction, onPressed: _goNextLesson),
      ]));
    }

    final q = _questions[_currentQ];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AColors.ink, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
              child: Center(child: Text('${_currentQ + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AColors.ink))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Question ${_currentQ + 1} of ${_questions.length}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const Text('Checkpoint Quiz',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        ACard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q['question'] as String? ?? '',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.ink, height: 1.4)),
            const SizedBox(height: 16),

            // MCQ options (when the backend provides them)
            if ((q['options'] as Map<String, dynamic>?)?.isNotEmpty == true) ...() {
              final options = q['options'] as Map<String, dynamic>;
              final correctKey = (_answerResult?['correct_answer'] as String?)?.trim().toUpperCase();
              return options.entries.map((e) {
                final key      = e.key.trim().toUpperCase();
                final isSel    = _selectedOption?.toUpperCase() == key;
                final isCorr   = _submitted && correctKey == key;
                final isWrong  = _submitted && isSel && !isCorr;
                Color bg = AColors.bg, border = AColors.cardBorder;
                if (isCorr)       { bg = AColors.greenSoft; border = AColors.green; }
                else if (isWrong) { bg = AColors.redSoft;   border = AColors.red;   }
                else if (isSel)   { bg = AColors.amberSoft; border = AColors.amber; }
                return GestureDetector(
                  onTap: (_submitted || _processingAction) ? null : () => _submitAnswer(key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border)),
                    child: Row(children: [
                      Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                            color: isSel ? AColors.ink : AColors.bg2,
                            border: Border.all(color: border)),
                        child: Center(child: Text(e.key,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: isSel ? Colors.white : AColors.textMuted))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value as String? ?? '',
                          style: const TextStyle(fontSize: 13, color: AColors.ink))),
                      if (isCorr)  Icon(Icons.check_circle_rounded, size: 16, color: AColors.green),
                      if (isWrong) Icon(Icons.cancel_rounded, size: 16, color: AColors.red),
                    ]),
                  ),
                );
              }).toList();
            }(),

            // Free-form text answer fallback (no options provided)
            if ((q['options'] as Map<String, dynamic>?)?.isEmpty != false && !_submitted) ...[
              TextField(
                controller: _answerCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Type your answer here…',
                  filled: true,
                  fillColor: AColors.bg2,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AColors.cardBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AColors.cardBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AColors.amber, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Claude will evaluate your answer intelligently.',
                  style: TextStyle(fontSize: 11, color: AColors.textMuted)),
            ],

            // Result feedback
            if (_submitted && _answerResult != null) ...[
              // "Your answer" box only needed for free-form; MCQ options are already highlighted above
              if (_selectedOption == null && _answerCtrl.text.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AColors.bg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AColors.cardBorder),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Your answer:', style: TextStyle(fontSize: 11, color: AColors.textMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_answerCtrl.text, style: const TextStyle(fontSize: 13, color: AColors.ink)),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_answerResult!['correct'] == true) ? AColors.greenSoft : AColors.redSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon((_answerResult!['correct'] == true)
                        ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 16,
                        color: (_answerResult!['correct'] == true) ? AColors.green : AColors.red),
                    const SizedBox(width: 6),
                    Text((_answerResult!['correct'] == true) ? 'Correct!' : 'Not quite right',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13,
                            color: (_answerResult!['correct'] == true) ? AColors.green : AColors.red)),
                  ]),
                  if ((_answerResult!['correct_answer'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    const Text('Correct answer:', style: TextStyle(fontSize: 11, color: AColors.textMuted, fontWeight: FontWeight.w600)),
                    Text(_answerResult!['correct_answer'] as String,
                        style: const TextStyle(fontSize: 13, color: AColors.textSecond)),
                  ],
                  if ((_answerResult!['explanation'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(_answerResult!['explanation'] as String,
                        style: const TextStyle(fontSize: 12, color: AColors.textSecond, height: 1.4)),
                  ],
                ]),
              ),
            ],

            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              // MCQ auto-submits on tap — only show "Submit" for the free-form fallback
              if (!_submitted && (q['options'] as Map<String, dynamic>?)?.isEmpty != false)
                AButton(
                  label: 'Submit Answer',
                  loading: _processingAction,
                  onPressed: _answerCtrl.text.trim().isEmpty || _processingAction ? null : _submitAnswer,
                )
              else if (_submitted)
                AButton(
                  label: _currentQ + 1 < _questions.length ? 'Next Question' : 'See Results',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _nextQuestion,
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStructuredQuiz() {
    return QuizPlayerWidget(
      questions: _questions,
      title: widget.lesson?.title ?? 'Quiz',
      onComplete: _goNextLesson,
    );
  }

  Widget _buildScore() {
    final pct = _questions.isNotEmpty ? (_correctCount / _questions.length * 100).round() : 0;
    final passed = pct >= 70;
    return Center(
      child: ACard(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: passed ? AColors.greenSoft : AColors.amberSoft, shape: BoxShape.circle),
            child: Center(child: Text('$pct%',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: passed ? AColors.green : AColors.amber))),
          ),
          const SizedBox(height: 16),
          Text(passed ? 'Great job!' : 'Keep going!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AColors.ink)),
          const SizedBox(height: 8),
          Text('$_correctCount of ${_questions.length} correct',
              style: const TextStyle(fontSize: 14, color: AColors.textMuted)),
          const SizedBox(height: 24),
          if (_actionError != null)
            Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text(_actionError!, style: const TextStyle(fontSize: 12, color: AColors.red))),
          AButton(
            label: 'Continue to Next Lesson',
            icon: Icons.arrow_forward_rounded,
            loading: _processingAction,
            onPressed: _processingAction ? null : _goNextLesson,
          ),
        ]),
      ),
    );
  }

  Widget _buildDone() {
    return Center(
      child: ACard(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: AColors.amberSoft, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.workspace_premium_rounded, size: 48, color: AColors.amber),
          ),
          const SizedBox(height: 16),
          const Text('Course Complete!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AColors.ink)),
          const SizedBox(height: 8),
          const Text('You\'ve finished all lessons.',
              style: TextStyle(fontSize: 14, color: AColors.textMuted)),
          const SizedBox(height: 24),
          AButton(label: 'Back to Catalog', icon: Icons.library_books_rounded,
              onPressed: () => context.go('/learner/catalog')),
        ]),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.render});
  final VideoRender render;

  @override
  Widget build(BuildContext context) {
    final url = VideoService.downloadUrl(render.renderId);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AColors.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AColors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.play_circle_filled_rounded, color: AColors.amber, size: 28),
        ),
        const SizedBox(width: 14),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Video Available', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          Text('Rendered lesson video — click to watch', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        AButton(
          label: 'Watch Video',
          variant: AButtonVariant.primary,
          size: AButtonSize.sm,
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      ]),
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard(this.slide);
  final CourseSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AColors.bg2, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Slide ${slide.slideNumber}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AColors.textMuted, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        ...slide.bullets.map((b) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(margin: const EdgeInsets.only(top: 6, right: 8),
                width: 4, height: 4,
                decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle)),
            Expanded(child: Text(b, style: const TextStyle(fontSize: 13, color: AColors.textSecond, height: 1.4))),
          ]),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tutor Chat Panel
// ─────────────────────────────────────────────────────────────────
class _TutorPanel extends StatefulWidget {
  const _TutorPanel({required this.sessionId, this.sessionError});
  final String? sessionId;
  final String? sessionError;
  @override
  State<_TutorPanel> createState() => _TutorPanelState();
}

class _TutorPanelState extends State<_TutorPanel> {
  final List<_Msg> _messages = [];
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  String? _prevSession;

  @override
  void didUpdateWidget(_TutorPanel old) {
    super.didUpdateWidget(old);
    if (widget.sessionId != null && widget.sessionId != _prevSession) {
      _prevSession = widget.sessionId;
      _messages.clear();
      _addMsg('assistant', 'Hi! I\'m Arresto AI. Ask me anything about this lesson.');
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) {
      _prevSession = widget.sessionId;
      _addMsg('assistant', 'Hi! I\'m Arresto AI. Ask me anything about this lesson.');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _addMsg(String role, String content) {
    setState(() => _messages.add(_Msg(role, content)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.sessionId == null || _sending) return;
    _ctrl.clear();
    _addMsg('user', text);
    setState(() => _sending = true);
    try {
      final data = await TutorService.chat(widget.sessionId!, text);
      final reply = data['reply'] as String? ?? '...';
      if (mounted) _addMsg('assistant', reply);
    } catch (e) {
      if (mounted) _addMsg('assistant', 'Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.sessionId != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 620),
      child: Container(
        decoration: BoxDecoration(
          color: AColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AColors.cardBorder),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: AColors.ink,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
            child: Row(children: [
              Container(width: 32, height: 32,
                  decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
                  child: const Center(child: Text('AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AColors.ink)))),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Arresto AI Tutor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Powered by Claude', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ])),
              if (!ready) const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AColors.amber)),
            ]),
          ),
          Expanded(child: ready
              ? ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _Bubble(_messages[i]),
                )
              : Center(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.sessionError != null
                        ? 'Tutor unavailable: ${widget.sessionError}'
                        : 'Connecting to tutor…',
                    style: const TextStyle(fontSize: 12, color: AColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ))),
          if (_sending) const LinearProgressIndicator(color: AColors.amber, backgroundColor: AColors.bg2, minHeight: 2),
          if (ready)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ask about this lesson…',
                      hintStyle: const TextStyle(color: AColors.textMuted, fontSize: 13),
                      filled: true, fillColor: AColors.bg2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 38, height: 38,
                    decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, size: 18, color: AColors.ink),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Msg {
  final String role, content;
  _Msg(this.role, this.content);
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.msg);
  final _Msg msg;
  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser ? AColors.ink : AColors.bg2,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isUser ? 12 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 12),
            ),
          ),
          child: isUser
              ? Text(msg.content,
                  style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4))
              : MarkdownBody(
                  data: msg.content,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 13, color: AColors.ink, height: 1.4),
                    strong: const TextStyle(fontSize: 13, color: AColors.ink, fontWeight: FontWeight.w700),
                    em: const TextStyle(fontSize: 13, color: AColors.ink, fontStyle: FontStyle.italic),
                    listBullet: const TextStyle(fontSize: 13, color: AColors.ink, height: 1.4),
                    code: const TextStyle(fontSize: 12, color: AColors.textSecond, fontFamily: 'monospace'),
                    codeblockDecoration: BoxDecoration(
                      color: AColors.bg2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    blockSpacing: 6,
                  ),
                ),
        ),
      ),
    );
  }
}
