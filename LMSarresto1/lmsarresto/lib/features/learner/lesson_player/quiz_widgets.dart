/// Shared quiz widgets used by both item_player_screen.dart (custom courses)
/// and lesson_player_screen.dart (module courses with embedded quiz questions).
library;

import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_card.dart';

// ── Quiz Player ────────────────────────────────────────────────────────────────

class QuizPlayerWidget extends StatefulWidget {
  const QuizPlayerWidget({
    super.key,
    required this.questions,
    required this.title,
    required this.onComplete,
  });
  final List<Map<String, dynamic>> questions;
  final String title;
  final VoidCallback onComplete;

  @override
  State<QuizPlayerWidget> createState() => _QuizPlayerWidgetState();
}

class _QuizPlayerWidgetState extends State<QuizPlayerWidget> {
  int     _idx       = 0;
  bool    _answered  = false;
  String? _selected;
  bool?   _isCorrect;
  bool    _flipped   = false;

  void _next() {
    if (_idx + 1 >= widget.questions.length) { widget.onComplete(); return; }
    setState(() { _idx++; _answered = false; _selected = null; _isCorrect = null; _flipped = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Center(child: AButton(label: 'Continue', onPressed: widget.onComplete));
    }
    final q     = widget.questions[_idx];
    final qType = q['type'] as String? ?? 'mcq';

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AColors.ink, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
              child: Center(child: Text('${_idx + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AColors.ink))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Question ${_idx + 1} of ${widget.questions.length}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              Text(widget.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ])),
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(_typeBadge(qType),
                  style: const TextStyle(fontSize: 10, color: Colors.white70,
                      fontWeight: FontWeight.w600, letterSpacing: 0.4)),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Question body
        ACard(
          child: switch (qType) {
            'mcq'       => McqQuestionWidget(
                q: q, answered: _answered, selected: _selected, isCorrect: _isCorrect,
                onSelect: (v) {
                  if (_answered) return;
                  setState(() { _selected = v; _answered = true; _isCorrect = v == (q['correct'] as String?); });
                }),
            'true_false' => TrueFalseQuestionWidget(
                q: q, answered: _answered, selected: _selected, isCorrect: _isCorrect,
                onSelect: (v) {
                  if (_answered) return;
                  final correct = (q['answer'] as bool?) == true ? 'true' : 'false';
                  setState(() { _selected = v; _answered = true; _isCorrect = v == correct; });
                }),
            'flashcard'  => FlashcardQuestionWidget(
                q: q, flipped: _flipped,
                onFlip: () => setState(() => _flipped = !_flipped)),
            _            => Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Unknown question type: $qType',
                    style: const TextStyle(color: AColors.textMuted))),
          },
        ),

        // Continue button
        if (_answered || qType == 'flashcard') ...[
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            AButton(
              label: _idx + 1 >= widget.questions.length ? 'Finish Quiz' : 'Next Question',
              icon: Icons.arrow_forward_rounded,
              onPressed: _next,
            ),
          ]),
        ],
        const SizedBox(height: 16),
      ]),
    );
  }

  static String _typeBadge(String type) => switch (type) {
    'mcq'        => 'MCQ',
    'true_false' => 'TRUE / FALSE',
    'flashcard'  => 'FLASHCARD',
    _            => type.toUpperCase(),
  };
}

// ── MCQ ────────────────────────────────────────────────────────────────────────

class McqQuestionWidget extends StatelessWidget {
  const McqQuestionWidget({
    super.key,
    required this.q,
    required this.answered,
    required this.selected,
    required this.isCorrect,
    required this.onSelect,
  });
  final Map<String, dynamic> q;
  final bool answered;
  final String? selected;
  final bool? isCorrect;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final question    = q['question']    as String? ?? '';
    final options     = (q['options']    as Map<String, dynamic>?) ?? {};
    final correct     = q['correct']     as String?;
    final explanation = q['explanation'] as String?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: AColors.ink, height: 1.4)),
      const SizedBox(height: 16),
      ...options.entries.map((e) {
        final isSel  = selected == e.key;
        final isCorr = e.key == correct;
        Color bg = AColors.bg, border = AColors.cardBorder;
        if (answered) {
          if (isCorr)       { bg = AColors.greenSoft; border = AColors.green; }
          else if (isSel)   { bg = AColors.redSoft;   border = AColors.red;   }
        } else if (isSel)   { bg = AColors.amberSoft; border = AColors.amber; }
        return GestureDetector(
          onTap: () => onSelect(e.key),
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
                child: Center(child: Text(e.key, style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSel ? Colors.white : AColors.textMuted))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(e.value as String? ?? '',
                  style: const TextStyle(fontSize: 13, color: AColors.ink))),
            ]),
          ),
        );
      }),
      if (answered && explanation != null && explanation.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: isCorrect == true ? AColors.greenSoft : AColors.redSoft,
              borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isCorrect == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 16, color: isCorrect == true ? AColors.green : AColors.red),
              const SizedBox(width: 6),
              Text(isCorrect == true ? 'Correct!' : 'Not quite',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                      color: isCorrect == true ? AColors.green : AColors.red)),
            ]),
            const SizedBox(height: 4),
            Text(explanation, style: const TextStyle(fontSize: 12,
                color: AColors.textSecond, height: 1.4)),
          ]),
        ),
      ],
    ]);
  }
}

// ── True / False ───────────────────────────────────────────────────────────────

class TrueFalseQuestionWidget extends StatelessWidget {
  const TrueFalseQuestionWidget({
    super.key,
    required this.q,
    required this.answered,
    required this.selected,
    required this.isCorrect,
    required this.onSelect,
  });
  final Map<String, dynamic> q;
  final bool answered;
  final String? selected;
  final bool? isCorrect;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final statement   = q['statement']   as String? ?? '';
    final explanation = q['explanation'] as String?;
    final correctVal  = (q['answer'] as bool?) == true ? 'true' : 'false';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(statement, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: AColors.ink, height: 1.4)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: TFButtonWidget(label: 'True',  value: 'true',
            selected: selected, answered: answered, isCorrectValue: correctVal,
            onTap: () => onSelect('true'))),
        const SizedBox(width: 12),
        Expanded(child: TFButtonWidget(label: 'False', value: 'false',
            selected: selected, answered: answered, isCorrectValue: correctVal,
            onTap: () => onSelect('false'))),
      ]),
      if (answered && explanation != null && explanation.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: isCorrect == true ? AColors.greenSoft : AColors.redSoft,
              borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(isCorrect == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 16, color: isCorrect == true ? AColors.green : AColors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(explanation,
                style: const TextStyle(fontSize: 12, color: AColors.textSecond, height: 1.4))),
          ]),
        ),
      ],
    ]);
  }
}

class TFButtonWidget extends StatelessWidget {
  const TFButtonWidget({
    super.key,
    required this.label,
    required this.value,
    required this.selected,
    required this.answered,
    required this.isCorrectValue,
    required this.onTap,
  });
  final String label, value, isCorrectValue;
  final String? selected;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSel  = selected == value;
    final isCorr = value == isCorrectValue;
    Color bg = AColors.bg, border = AColors.cardBorder, text = AColors.textSecond;
    if (answered) {
      if (isCorr)     { bg = AColors.greenSoft; border = AColors.green; text = AColors.green; }
      else if (isSel) { bg = AColors.redSoft;   border = AColors.red;   text = AColors.red;   }
    } else if (isSel) { bg = AColors.amberSoft; border = AColors.amber; text = AColors.orange; }
    return GestureDetector(
      onTap: answered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border)),
        child: Center(child: Text(label, style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w700, color: text))),
      ),
    );
  }
}

// ── Flashcard ──────────────────────────────────────────────────────────────────

class FlashcardQuestionWidget extends StatelessWidget {
  const FlashcardQuestionWidget({
    super.key,
    required this.q,
    required this.flipped,
    required this.onFlip,
  });
  final Map<String, dynamic> q;
  final bool flipped;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final front = q['front'] as String? ?? '';
    final back  = q['back']  as String? ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.flip_rounded, size: 14, color: AColors.textMuted),
        SizedBox(width: 6),
        Text('Flashcard — tap to flip',
            style: TextStyle(fontSize: 11, color: AColors.textMuted, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: onFlip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: flipped ? AColors.amberSoft : AColors.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: flipped ? AColors.amber : AColors.cardBorder, width: 1.5)),
          child: Column(children: [
            Icon(flipped ? Icons.lightbulb_rounded : Icons.help_outline_rounded,
                color: flipped ? AColors.amber : AColors.textMuted, size: 28),
            const SizedBox(height: 10),
            Text(flipped ? 'Answer' : 'Question',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: flipped ? AColors.orange : AColors.textMuted)),
            const SizedBox(height: 6),
            Text(flipped ? back : front,
                style: TextStyle(fontSize: 14, height: 1.5,
                    color: flipped ? AColors.ink : AColors.textSecond,
                    fontWeight: flipped ? FontWeight.w600 : FontWeight.w400),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Center(child: Text(
          flipped ? 'Tap to see question again' : 'Tap card to reveal answer',
          style: const TextStyle(fontSize: 11, color: AColors.textMuted))),
    ]);
  }
}
