import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_ai_logo.dart';
import '../../../core/services/assessment_service.dart';
import '../../../data/providers/api_providers.dart';

// ── local types ──────────────────────────────────────────────────────────────

enum _InputMode { choose, type }

class _LocalResult {
  final bool correct;
  final String correctAnswer;
  final String explanation;
  const _LocalResult({
    required this.correct,
    required this.correctAnswer,
    required this.explanation,
  });
}

// ── screen ───────────────────────────────────────────────────────────────────

class AssessmentQuizScreen extends ConsumerStatefulWidget {
  final String courseId;
  const AssessmentQuizScreen({super.key, required this.courseId});

  @override
  ConsumerState<AssessmentQuizScreen> createState() =>
      _AssessmentQuizScreenState();
}

class _AssessmentQuizScreenState extends ConsumerState<AssessmentQuizScreen> {
  Timer? _timer;
  int _secondsLeft   = 30 * 60;
  int _totalSeconds  = 30 * 60;
  int _currentIdx    = 0;
  bool _timerStarted = false;
  int _passPct       = 70;
  List<AssessmentQuestion> _loadedQuestions = [];
  final Set<int> _flagged = {};

  // questionId → selected option key (A/B/C/D)
  final Map<String, String> _answers = {};
  // questionId → graded result
  final Map<String, _LocalResult> _results = {};
  // questionId → input mode (choose / type)
  final Map<String, _InputMode> _modes = {};
  // questionId → typed answer draft
  final Map<String, TextEditingController> _typeCtrl = {};

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _typeCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String get _timeStr {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  _InputMode _modeFor(String qId) => _modes[qId] ?? _InputMode.choose;

  TextEditingController _ctrlFor(String qId) {
    return _typeCtrl.putIfAbsent(qId, () {
      final c = TextEditingController();
      c.addListener(() => setState(() {}));
      return c;
    });
  }

  void _startTimer(List<AssessmentQuestion> questions, int timeMin, int passPct) {
    if (_timerStarted) return;
    _timerStarted    = true;
    _loadedQuestions = questions;
    _passPct         = passPct;
    _totalSeconds    = timeMin * 60;
    setState(() => _secondsLeft = _totalSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        t.cancel();
        _submitAll(_loadedQuestions);
      }
    });
  }

  void _selectAnswer(AssessmentQuestion q, String optionKey) {
    if (_answers.containsKey(q.id)) return;
    setState(() {
      _answers[q.id] = optionKey;
      _results[q.id] = _LocalResult(
        correct:       optionKey == q.correctAnswer,
        correctAnswer: q.correctAnswer,
        explanation:   q.explanation,
      );
    });
  }

  void _submitTyped(AssessmentQuestion q, String text) {
    if (_answers.containsKey(q.id)) return;
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _answers[q.id] = t;
      _results[q.id] = _LocalResult(
        correct:       true, // open answers count as participation
        correctAnswer: q.correctAnswer,
        explanation:   q.explanation,
      );
    });
  }

  void _submitAll(List<AssessmentQuestion> questions) {
    _timer?.cancel();
    final correct = _results.values.where((r) => r.correct).length;
    final total   = questions.isNotEmpty ? questions.length : _answers.length;
    final score   = total == 0 ? 0 : ((correct / total) * 100).round();
    final elapsed = (_totalSeconds - _secondsLeft).clamp(0, _totalSeconds);

    final correctAnswers = {for (final q in questions) q.id: q.correctAnswer};
    final explanations   = {for (final q in questions) q.id: q.explanation};

    ref.read(quizResultsProvider.notifier).state = QuizResult(
      correct:        correct,
      total:          total,
      score:          score,
      elapsedSeconds: elapsed,
      passPct:        _passPct,
      answers:        Map.from(_answers),
      correctAnswers: correctAnswers,
      explanations:   explanations,
      questions:      questions,
    );

    AssessmentService.saveAttempt(
      courseId:       widget.courseId,
      learnerId:      ref.read(learnerIdProvider),
      score:          score,
      correct:        correct,
      total:          total,
      passed:         score >= _passPct,
      elapsedSeconds: elapsed,
      answers:        Map.from(_answers),
    );

    context.go('/learner/assessment/${widget.courseId}/result');
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(assessmentQuestionsProvider(widget.courseId));
    final detailAsync    = ref.watch(courseDetailProvider(widget.courseId));
    final detail         = detailAsync.valueOrNull;
    final timeMin        = (detail?['assessment_time_min'] as num?)?.toInt() ?? 30;
    final passPct        = (detail?['assessment_pass_pct'] as num?)?.toInt() ?? 70;

    return questionsAsync.when(
      loading: () => _scaffold(
        'Generating questions…',
        const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: ArrestoColors.orange),
            SizedBox(height: 16),
            Text('Generating AI questions for your course…'),
          ]),
        ),
      ),
      error: (e, _) => _scaffold(
        'Assessment',
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.smart_toy_rounded,
                  color: ArrestoColors.textMuted2, size: 48),
              const SizedBox(height: 16),
              Text('Could not load questions: $e',
                  style: ArrestoText.body(), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ArrestoButton(
                label: 'Go to Course',
                onPressed: () =>
                    context.go('/learner/course/${widget.courseId}'),
              ),
            ]),
          ),
        ),
      ),
      data: (questions) {
        if (questions.isEmpty) {
          return _scaffold(
            'Assessment',
            Center(
              child: Text(
                'No questions available. The course may still be generating.',
                style: ArrestoText.body(),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!_timerStarted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _startTimer(questions, timeMin, passPct),
          );
        }

        if (_currentIdx >= questions.length) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _currentIdx = questions.length - 1));
        }

        final idx        = _currentIdx.clamp(0, questions.length - 1);
        final q          = questions[idx];
        final isFlagged  = _flagged.contains(idx);
        final answered   = _answers.containsKey(q.id);
        final result     = _results[q.id];
        final isTF       = q.type == 'true_false';
        final mode       = _modeFor(q.id);
        final ctrl       = _ctrlFor(q.id);

        return Column(
          children: [
            // ── app bar with timer ──────────────────────────────────────
            AppBar(
              backgroundColor:       ArrestoColors.surface,
              foregroundColor:       ArrestoColors.ink,
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
              title: Row(children: [
                Text('Q ${idx + 1} / ${questions.length}',
                    style: ArrestoText.h4()),
                const Spacer(),
                // timer chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _secondsLeft < 300
                        ? ArrestoColors.redSoft
                        : ArrestoColors.bg2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(children: [
                    Icon(Icons.timer_rounded,
                        size: 14,
                        color: _secondsLeft < 300
                            ? ArrestoColors.red
                            : ArrestoColors.textMuted),
                    const SizedBox(width: 4),
                    Text(_timeStr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _secondsLeft < 300
                              ? ArrestoColors.red
                              : ArrestoColors.ink,
                        )),
                  ]),
                ),
                const SizedBox(width: 8),
                // flag chip
                GestureDetector(
                  onTap: () => setState(() {
                    if (_flagged.contains(idx)) _flagged.remove(idx);
                    else _flagged.add(idx);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFlagged
                          ? ArrestoColors.amberSoft
                          : ArrestoColors.bg2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isFlagged
                            ? ArrestoColors.amber
                            : ArrestoColors.line,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        isFlagged
                            ? Icons.flag_rounded
                            : Icons.flag_outlined,
                        size: 13,
                        color: isFlagged
                            ? ArrestoColors.amber
                            : ArrestoColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text('Flag',
                          style: ArrestoText.xs(
                              color: isFlagged
                                  ? ArrestoColors.amber
                                  : ArrestoColors.textMuted)),
                    ]),
                  ),
                ),
              ]),
            ),

            // ── progress bar ────────────────────────────────────────────
            LinearProgressIndicator(
              value:          (idx + 1) / questions.length,
              backgroundColor: ArrestoColors.line,
              valueColor:      const AlwaysStoppedAnimation(ArrestoColors.amber),
              minHeight:       3,
            ),

            // ── main content ────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Ishita-style question card ──
                    _QuestionCard(
                      q:        q,
                      isTF:     isTF,
                      mode:     mode,
                      answered: answered,
                      result:   result,
                      ctrl:     ctrl,
                      onModeChange: (m) =>
                          setState(() => _modes[q.id] = m),
                      onSelect: (key) => _selectAnswer(q, key),
                      onTypeSubmit: (text) => _submitTyped(q, text),
                    ),

                    const SizedBox(height: 20),

                    // ── question navigator dots ──
                    Text('Questions', style: ArrestoText.label()),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(questions.length, (i) {
                        final isCurrent  = i == idx;
                        final qId        = questions[i].id;
                        final isAnswered = _answers.containsKey(qId);
                        final isFlaggedQ = _flagged.contains(i);

                        Color bg, border, textColor;
                        if (isCurrent) {
                          bg        = ArrestoColors.orange;
                          border    = ArrestoColors.orange;
                          textColor = Colors.white;
                        } else if (isAnswered) {
                          bg        = ArrestoColors.greenSoft;
                          border    = ArrestoColors.green;
                          textColor = ArrestoColors.green;
                        } else if (isFlaggedQ) {
                          bg        = ArrestoColors.amberSoft;
                          border    = ArrestoColors.amber;
                          textColor = const Color(0xFF92400E);
                        } else {
                          bg        = ArrestoColors.surface;
                          border    = ArrestoColors.line;
                          textColor = ArrestoColors.textMuted;
                        }

                        return GestureDetector(
                          onTap: () => setState(() => _currentIdx = i),
                          child: Container(
                            width:  36,
                            height: 36,
                            decoration: BoxDecoration(
                              color:        bg,
                              borderRadius: BorderRadius.circular(8),
                              border:       Border.all(color: border),
                            ),
                            alignment: Alignment.center,
                            child: Text('${i + 1}',
                                style: TextStyle(
                                  fontSize:   12,
                                  fontWeight: FontWeight.w700,
                                  color:      textColor,
                                )),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),

            // ── bottom navigation ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: const BoxDecoration(
                color:  ArrestoColors.surface,
                border: Border(top: BorderSide(color: ArrestoColors.line)),
              ),
              child: Row(children: [
                if (idx > 0)
                  ArrestoButton(
                    label:    'Previous',
                    variant:  ArrestoButtonVariant.ghost,
                    icon:     const Icon(Icons.arrow_back_rounded),
                    onPressed: () => setState(() => _currentIdx = idx - 1),
                  ),
                const Spacer(),
                if (idx < questions.length - 1)
                  ArrestoButton(
                    label:     'Next',
                    icon:      const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => setState(() => _currentIdx = idx + 1),
                  )
                else
                  ArrestoButton(
                    label:     'Submit',
                    variant:   ArrestoButtonVariant.dark,
                    icon:      const Icon(Icons.check_rounded),
                    onPressed: () => _showSubmitDialog(context, questions),
                  ),
              ]),
            ),
          ],
        );
      },
    );
  }

  // ── submit confirmation dialog ─────────────────────────────────────────────

  void _showSubmitDialog(
      BuildContext context, List<AssessmentQuestion> questions) {
    final unanswered =
        questions.where((q) => !_answers.containsKey(q.id)).length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArrestoColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Submit Assessment?', style: ArrestoText.h3()),
        content: Text(
          unanswered > 0
              ? '$unanswered question${unanswered > 1 ? 's' : ''} unanswered. Submit anyway?'
              : 'Are you sure? You cannot change your answers after submission.',
          style: ArrestoText.body(),
        ),
        actions: [
          ArrestoButton(
            label:    'Cancel',
            variant:  ArrestoButtonVariant.ghost,
            onPressed: () => Navigator.pop(ctx),
          ),
          const SizedBox(width: 8),
          ArrestoButton(
            label:     'Submit',
            variant:   ArrestoButtonVariant.dark,
            onPressed: () {
              Navigator.pop(ctx);
              _submitAll(questions);
            },
          ),
        ],
      ),
    );
  }

  Widget _scaffold(String title, Widget body) => Column(children: [
    AppBar(
      backgroundColor: ArrestoColors.surface,
      foregroundColor: ArrestoColors.ink,
      title:           Text(title, style: ArrestoText.h4()),
      leading: IconButton(
        icon:      const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.pop(),
      ),
    ),
    Expanded(child: body),
  ]);
}

// ── Question card (Ishita-style) ─────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final AssessmentQuestion q;
  final bool isTF;
  final _InputMode mode;
  final bool answered;
  final _LocalResult? result;
  final TextEditingController ctrl;
  final ValueChanged<_InputMode> onModeChange;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onTypeSubmit;

  const _QuestionCard({
    required this.q,
    required this.isTF,
    required this.mode,
    required this.answered,
    required this.result,
    required this.ctrl,
    required this.onModeChange,
    required this.onSelect,
    required this.onTypeSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        ArrestoColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color:     Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset:    const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── brand header ──
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            child: Row(children: [
              const ArrestoAiLogo(size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Assessment question', style: ArrestoText.bodyBold()),
                  Text('Arresto AI · test your knowledge',
                      style: ArrestoText.xs()),
                ]),
              ),
            ]),
          ),

          const Divider(height: 1, color: ArrestoColors.line),

          // ── body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        isTF
                        ? ArrestoColors.amberSoft
                        : ArrestoColors.blueSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isTF ? 'True / False' : 'Multiple choice',
                    style: TextStyle(
                      fontSize:   11,
                      fontWeight: FontWeight.w700,
                      color:      isTF
                          ? ArrestoColors.orange
                          : ArrestoColors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(q.question, style: ArrestoText.h3()),
                const SizedBox(height: 16),

                // mode switcher — Choose / Type (only for non-TF when not answered)
                if (!isTF && !answered) ...[
                  _ModeSwitcher(mode: mode, onChanged: onModeChange),
                  const SizedBox(height: 16),
                ],

                // answer section
                if (mode == _InputMode.choose || isTF)
                  _ChooseSection(
                    q:        q,
                    isTF:     isTF,
                    answered: answered,
                    result:   result,
                    onSelect: onSelect,
                  )
                else
                  _TypeSection(
                    ctrl:      ctrl,
                    answered:  answered,
                    onSubmit:  onTypeSubmit,
                  ),

                // explanation
                if (answered && result != null) ...[
                  const SizedBox(height: 12),
                  _ExplanationBanner(result: result!),
                ],

                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode switcher ─────────────────────────────────────────────────────────────

class _ModeSwitcher extends StatelessWidget {
  final _InputMode mode;
  final ValueChanged<_InputMode> onChanged;

  const _ModeSwitcher({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const modes = [_InputMode.choose, _InputMode.type];
    IconData iconFor(_InputMode m) => switch (m) {
          _InputMode.choose => Icons.format_list_bulleted_rounded,
          _InputMode.type   => Icons.edit_rounded,
        };
    String labelFor(_InputMode m) => switch (m) {
          _InputMode.choose => 'Choose',
          _InputMode.type   => 'Type',
        };

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color:        ArrestoColors.bg2,
        borderRadius: BorderRadius.circular(999),
        border:       Border.all(color: ArrestoColors.line),
      ),
      child: Row(
        children: modes.map((m) {
          final active = m == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color:        active ? ArrestoColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow:    active ? ArrestoColors.sh1 : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(iconFor(m),
                        size:  15,
                        color: active ? ArrestoColors.orange : ArrestoColors.textMuted),
                    const SizedBox(width: 6),
                    Text(labelFor(m),
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          color:      active ? ArrestoColors.ink : ArrestoColors.textMuted,
                        )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Choose section (MCQ + True/False) ─────────────────────────────────────────

class _ChooseSection extends StatelessWidget {
  final AssessmentQuestion q;
  final bool isTF;
  final bool answered;
  final _LocalResult? result;
  final ValueChanged<String> onSelect;

  const _ChooseSection({
    required this.q,
    required this.isTF,
    required this.answered,
    required this.result,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (isTF) return _trueFalse();
    return _mcq();
  }

  Widget _mcq() {
    final opts = q.options.entries.toList();
    return Column(
      children: opts.map((opt) {
        final isSelected  = result != null
            ? (result!.correct
                ? opt.key == result!.correctAnswer
                : false)
            : false;
        // before answering we can't know which was clicked — track via answered flag
        final wasSelected = answered && opt.key == (result?.correctAnswer == opt.key
            ? (result?.correct == true ? opt.key : '__none__')
            : '__none__');

        // simpler approach: highlight correct always after answer,
        // and the user's choice if wrong
        final isCorrectOpt = answered && opt.key == result?.correctAnswer;

        Color bg          = ArrestoColors.surface;
        Color borderColor = ArrestoColors.line;
        double borderW    = 1;

        if (answered) {
          if (isCorrectOpt) {
            bg          = ArrestoColors.greenSoft;
            borderColor = ArrestoColors.green;
            borderW     = 1.5;
          }
        }

        return GestureDetector(
          onTap: answered ? null : () => onSelect(opt.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color:        bg,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: borderColor, width: borderW),
            ),
            child: Row(children: [
              Container(
                width:  28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCorrectOpt && answered
                      ? ArrestoColors.green
                      : ArrestoColors.bg2,
                ),
                alignment: Alignment.center,
                child: Text(
                  opt.key,
                  style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w700,
                    color:      isCorrectOpt && answered
                        ? Colors.white
                        : ArrestoColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(opt.value, style: ArrestoText.bodyBold()),
              ),
              if (answered && isCorrectOpt)
                const Icon(Icons.check_circle_rounded,
                    color: ArrestoColors.green, size: 20),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _trueFalse() {
    final entries = q.options.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Row(
      children: entries.asMap().entries.map((e) {
        final i    = e.key;
        final opt  = e.value;
        final isTrue      = opt.value.toLowerCase() == 'true';
        final isCorrectOpt = answered && opt.key == result?.correctAnswer;

        Color bg        = ArrestoColors.bg2;
        Color border    = ArrestoColors.line;
        Color textColor = ArrestoColors.textMuted;
        Color iconColor = ArrestoColors.textMuted2;

        if (answered && isCorrectOpt) {
          bg        = ArrestoColors.greenSoft;
          border    = ArrestoColors.green;
          textColor = ArrestoColors.green;
          iconColor = ArrestoColors.green;
        }

        return Expanded(
          child: GestureDetector(
            onTap: answered ? null : () => onSelect(opt.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(right: i == 0 ? 8 : 0, left: i == 0 ? 0 : 8),
              height: 110,
              decoration: BoxDecoration(
                color:        bg,
                borderRadius: BorderRadius.circular(16),
                border:       Border.all(color: border, width: answered && isCorrectOpt ? 1.5 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isTrue ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: iconColor,
                    size:  32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    opt.value,
                    style: TextStyle(
                      fontSize:   20,
                      fontWeight: FontWeight.w800,
                      color:      textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Type section ──────────────────────────────────────────────────────────────

class _TypeSection extends StatelessWidget {
  final TextEditingController ctrl;
  final bool answered;
  final ValueChanged<String> onSubmit;

  const _TypeSection({
    required this.ctrl,
    required this.answered,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final len = ctrl.text.characters.length;
    const max = 400;
    if (answered) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        ArrestoColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: ArrestoColors.line),
        ),
        child: Text(ctrl.text.isEmpty ? '(answered)' : ctrl.text,
            style: ArrestoText.body()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: ctrl,
          minLines:   3,
          maxLines:   6,
          maxLength:  max,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          decoration: const InputDecoration(
            hintText: 'Type your answer…',
            border:   OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$len / $max',
              style: ArrestoText.xs(
                  color: len >= max ? ArrestoColors.red : ArrestoColors.textMuted)),
          FilledButton(
            onPressed: len > 0 ? () => onSubmit(ctrl.text) : null,
            style: FilledButton.styleFrom(
              backgroundColor: ArrestoColors.amber,
              foregroundColor: ArrestoColors.ink,
              padding:         const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape:           RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle:       const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
            ),
            child: const Text('Submit answer'),
          ),
        ]),
      ],
    );
  }
}

// ── Explanation banner ────────────────────────────────────────────────────────

class _ExplanationBanner extends StatelessWidget {
  final _LocalResult result;
  const _ExplanationBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        result.correct ? ArrestoColors.greenSoft : ArrestoColors.redSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.correct
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: result.correct ? ArrestoColors.green : ArrestoColors.red,
            size:  18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.explanation.isNotEmpty
                  ? result.explanation
                  : (result.correct
                      ? 'Correct!'
                      : 'Incorrect. The correct answer is ${result.correctAnswer}.'),
              style: ArrestoText.body(
                  color: result.correct ? ArrestoColors.green : ArrestoColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
