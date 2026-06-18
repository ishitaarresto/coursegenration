import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../data/providers/api_providers.dart';

class AssessmentFlashcardsScreen extends ConsumerStatefulWidget {
  final String courseId;
  const AssessmentFlashcardsScreen({super.key, required this.courseId});

  @override
  ConsumerState<AssessmentFlashcardsScreen> createState() =>
      _AssessmentFlashcardsScreenState();
}

class _AssessmentFlashcardsScreenState
    extends ConsumerState<AssessmentFlashcardsScreen>
    with SingleTickerProviderStateMixin {
  int _currentIdx = 0;
  bool _currentFlipped = false;
  final Map<int, bool> _seen = {};

  late final AnimationController _flipCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _flipAnim = CurvedAnimation(
    parent: _flipCtrl,
    curve: Curves.easeInOut,
  );

  void _flip() {
    if (_flipCtrl.isAnimating) return;
    if (_currentFlipped) {
      _flipCtrl.reverse();
      setState(() => _currentFlipped = false);
    } else {
      _flipCtrl.forward();
      setState(() {
        _currentFlipped = true;
        _seen[_currentIdx] = true;
      });
    }
  }

  void _navigateTo(int idx) {
    if (_flipCtrl.value > 0) {
      _flipCtrl.animateTo(0, duration: const Duration(milliseconds: 200));
    }
    setState(() {
      _currentIdx = idx;
      _currentFlipped = false;
    });
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync =
        ref.watch(assessmentQuestionsProvider(widget.courseId));
    return questionsAsync.when(
      loading: () => _shell(
        'Generating questions…',
        const Center(
            child: CircularProgressIndicator(color: ArrestoColors.orange)),
      ),
      error: (e, _) => _shell(
        'Study Mode',
        Center(child: Text('Failed to load: $e', style: ArrestoText.body())),
      ),
      data: (questions) {
        if (questions.isEmpty) {
          return _shell(
            'Study Mode',
            Center(
                child: Text('No questions available.', style: ArrestoText.body())),
          );
        }

        final q = questions[_currentIdx];
        final correctText = q.options[q.correctAnswer] ?? q.correctAnswer;
        final seenCount = _seen.values.where((v) => v).length;

        return Column(children: [
          AppBar(
            backgroundColor: ArrestoColors.surface,
            foregroundColor: ArrestoColors.ink,
            automaticallyImplyLeading: false,
            title: Row(children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.pop(),
              ),
              Text('Study Mode', style: ArrestoText.h4()),
              const Spacer(),
              Text('$seenCount / ${questions.length} seen',
                  style: ArrestoText.small(color: ArrestoColors.textMuted)),
            ]),
          ),
          LinearProgressIndicator(
            value: (_currentIdx + 1) / questions.length,
            backgroundColor: ArrestoColors.line,
            valueColor: const AlwaysStoppedAnimation(ArrestoColors.amber),
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '${_currentIdx + 1} of ${questions.length}',
              style: ArrestoText.smallBold(color: ArrestoColors.textMuted),
            ),
          ),

          // ── Flip card ─────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: _flip,
                child: AnimatedBuilder(
                  animation: _flipAnim,
                  builder: (context, _) {
                    final angle = _flipAnim.value * math.pi;
                    final showBack = _flipAnim.value > 0.5;
                    return Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(angle),
                      alignment: Alignment.center,
                      child: showBack
                          ? Transform(
                              transform: Matrix4.identity()..rotateY(math.pi),
                              alignment: Alignment.center,
                              child: _BackCard(
                                answer: correctText,
                                explanation: q.explanation,
                              ),
                            )
                          : _FrontCard(question: q.question, type: q.type),
                    );
                  },
                ),
              ),
            ),
          ),

          // Hint
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              _currentFlipped ? 'Tap to flip back' : 'Tap card to reveal answer',
              style: ArrestoText.xs(color: ArrestoColors.textMuted),
            ),
          ),

          // Progress dots — orange = current, green = seen, grey = unseen
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 6,
              children: List.generate(questions.length, (i) {
                final isSeen = _seen[i] ?? false;
                final isCurrent = i == _currentIdx;
                return GestureDetector(
                  onTap: () => _navigateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isCurrent ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isCurrent
                          ? ArrestoColors.orange
                          : isSeen
                              ? ArrestoColors.green
                              : ArrestoColors.line,
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Navigation bar ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: const BoxDecoration(
              color: ArrestoColors.surface,
              border: Border(top: BorderSide(color: ArrestoColors.line)),
            ),
            child: Row(children: [
              if (_currentIdx > 0)
                ArrestoButton(
                  label: 'Previous',
                  variant: ArrestoButtonVariant.ghost,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => _navigateTo(_currentIdx - 1),
                ),
              const Spacer(),
              if (_currentIdx < questions.length - 1)
                ArrestoButton(
                  label: 'Next Card',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _navigateTo(_currentIdx + 1),
                )
              else
                ArrestoButton(
                  label: 'Take Assessment',
                  variant: ArrestoButtonVariant.dark,
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => context
                      .go('/learner/assessment/${widget.courseId}/quiz'),
                ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _shell(String title, Widget body) {
    return Column(children: [
      AppBar(
        backgroundColor: ArrestoColors.surface,
        foregroundColor: ArrestoColors.ink,
        title: Text(title, style: ArrestoText.h4()),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      Expanded(child: body),
    ]);
  }
}

// ── Front of card (question) ──────────────────────────────────────────────────
class _FrontCard extends StatelessWidget {
  final String question;
  final String type;
  const _FrontCard({required this.question, required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ArrestoColors.ink,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: ArrestoColors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              type == 'true_false' ? 'True / False' : 'Multiple Choice',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ArrestoColors.amber,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            question,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.touch_app_rounded,
                size: 14, color: Color(0xFF9CA3AF)),
            const SizedBox(width: 6),
            Text('Tap to reveal',
                style: ArrestoText.xs(color: const Color(0xFF9CA3AF))),
          ]),
        ],
      ),
    );
  }
}

// ── Back of card (answer + explanation) ──────────────────────────────────────
class _BackCard extends StatelessWidget {
  final String answer;
  final String explanation;
  const _BackCard({required this.answer, required this.explanation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF065F46)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 20),
          Text(
            answer,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Text(
                explanation,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
