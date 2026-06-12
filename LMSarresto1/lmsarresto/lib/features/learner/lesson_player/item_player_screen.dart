import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/theme/colors.dart';
import '../../../core/api/course_service.dart';
import '../../../core/api/audio_service.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_card.dart';
import 'quiz_widgets.dart';

// ─────────────────────────────────────────────────────────────────
// Item Player — for courses using the flat `items` format
// Route: /learner/play/:courseId/:itemIndex
// ─────────────────────────────────────────────────────────────────
class ItemPlayerScreen extends ConsumerStatefulWidget {
  const ItemPlayerScreen({
    super.key,
    required this.scriptId,
    required this.startIndex,
  });
  final String scriptId;
  final int startIndex;

  @override
  ConsumerState<ItemPlayerScreen> createState() => _ItemPlayerScreenState();
}

class _ItemPlayerScreenState extends ConsumerState<ItemPlayerScreen> {
  CourseScript? _script;
  bool _loading = true;
  String? _error;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _load();
  }

  Future<void> _load() async {
    try {
      final script = await CourseService.getScript(widget.scriptId);
      if (mounted) setState(() { _script = script; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _goTo(int index) {
    final items = _script?.items ?? [];
    if (index < 0 || index >= items.length) return;
    setState(() => _currentIndex = index);
    context.go('/learner/play/${widget.scriptId}/$index');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    final script = _script!;
    final items = script.items;

    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.warning_amber_rounded, size: 48, color: AColors.amber),
        const SizedBox(height: 12),
        const Text('No content available', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AColors.ink)),
        const SizedBox(height: 8),
        const Text('This course does not have any content yet.', style: TextStyle(color: AColors.textMuted)),
        const SizedBox(height: 20),
        AButton(label: 'Back to Catalog', onPressed: () => context.go('/learner/catalog')),
      ]));
    }

    if (_currentIndex >= items.length) {
      return _DoneScreen(onBack: () => context.go('/learner/catalog'));
    }

    final item = items[_currentIndex];
    final progress = (_currentIndex + 1) / items.length;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        // Progress bar + title
        Row(children: [
          AButton(
            label: '', icon: Icons.arrow_back_rounded,
            variant: AButtonVariant.ghost,
            size: AButtonSize.sm,
            onPressed: () {
              if (_currentIndex > 0) _goTo(_currentIndex - 1);
              else context.go('/learner/catalog/${widget.scriptId}');
            },
          ),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(script.title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AColors.bg2,
                  valueColor: const AlwaysStoppedAnimation(AColors.amber),
                ),
              )),
              const SizedBox(width: 8),
              Text('${_currentIndex + 1}/${items.length}',
                  style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
            ]),
          ])),
        ]),
        const SizedBox(height: 16),

        // Item content
        Expanded(child: _buildItem(item, items.length)),
      ]),
    );
  }

  Widget _buildItem(CourseItem item, int total) {
    switch (item.type) {
      case 'quiz':
        final questions = (item.raw['questions'] as List? ?? [])
            .map((q) => q as Map<String, dynamic>).toList();
        return QuizPlayerWidget(
          questions: questions,
          title: item.title,
          onComplete: () => _currentIndex + 1 >= total
              ? setState(() => _currentIndex = total)
              : _goTo(_currentIndex + 1),
        );
      case 'closing_slide':
        return _SlideView(
          item: item,
          isLast: true,
          scriptId: widget.scriptId,
          itemIndex: _currentIndex,
          onNext: () => setState(() => _currentIndex = total),
        );
      default: // 'slide'
        return _SlideView(
          item: item,
          isLast: _currentIndex + 1 >= total,
          scriptId: widget.scriptId,
          itemIndex: _currentIndex,
          onNext: () => _currentIndex + 1 >= total
              ? setState(() => _currentIndex = total)
              : _goTo(_currentIndex + 1),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Slide View
// ─────────────────────────────────────────────────────────────────
class _SlideView extends StatefulWidget {
  const _SlideView({
    required this.item, required this.isLast,
    required this.scriptId, required this.itemIndex,
    required this.onNext,
  });
  final CourseItem item;
  final bool isLast;
  final String scriptId;
  final int itemIndex;
  final VoidCallback onNext;

  @override
  State<_SlideView> createState() => _SlideViewState();
}

class _SlideViewState extends State<_SlideView> {
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  bool _audioLoading = false;
  bool _audioError = false;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _playerState = s); }));
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (_playerState == PlayerState.playing) { await _player.pause(); return; }
    if (_playerState == PlayerState.paused)  { await _player.resume(); return; }
    setState(() { _audioLoading = true; _audioError = false; });
    try {
      // Items use module 1, lesson = item_index + 1 as a convention for audio
      final url = AudioService.lessonAudioUrl(widget.scriptId, 1, widget.itemIndex + 1);
      await _player.play(UrlSource(url));
    } catch (_) {
      if (mounted) setState(() => _audioError = true);
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final narration = item.narration;
    final bullets = item.bullets;
    final example = item.raw['example'] as String?;
    final takeaway = item.raw['takeaway'] as String?;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Audio bar
        ACard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            GestureDetector(
              onTap: _audioLoading ? null : _toggleAudio,
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
                child: _audioLoading
                    ? const Center(child: SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AColors.ink)))
                    : Icon(_playerState == PlayerState.playing
                        ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: AColors.ink, size: 26),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AColors.ink)),
              if (_audioError)
                const Text('Audio not generated yet',
                    style: TextStyle(fontSize: 11, color: AColors.textMuted))
              else
                Text(_playerState == PlayerState.playing ? 'Playing narration…' : 'Tap to listen',
                    style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Narration
        if (narration.isNotEmpty)
          APanel(
            title: 'Narration',
            child: Text(narration,
                style: const TextStyle(fontSize: 14, color: AColors.textSecond, height: 1.7)),
          ),

        // Bullets
        if (bullets.isNotEmpty) ...[
          const SizedBox(height: 16),
          APanel(
            title: 'Key Points',
            child: Column(children: bullets.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
                ),
                Expanded(child: Text(b, style: const TextStyle(fontSize: 14, color: AColors.textSecond, height: 1.5))),
              ]),
            )).toList()),
          ),
        ],

        // Example
        if (example != null && example.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AColors.amberSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AColors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.person_outline_rounded, color: AColors.orange, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Worker Example', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AColors.orange, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(example, style: const TextStyle(fontSize: 13, color: AColors.ink, height: 1.5)),
              ])),
            ]),
          ),
        ],

        // Takeaway
        if (takeaway != null && takeaway.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AColors.ink,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline_rounded, color: AColors.amber, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(takeaway,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: Colors.white, height: 1.4))),
            ]),
          ),
        ],

        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AButton(
            label: widget.isLast ? 'Complete Course' : 'Next',
            icon: widget.isLast ? Icons.workspace_premium_rounded : Icons.arrow_forward_rounded,
            onPressed: widget.onNext,
          ),
        ]),
        const SizedBox(height: 16),
      ]),
    );
  }
}


// ─────────────────────────────────────────────────────────────────
// Done screen
// ─────────────────────────────────────────────────────────────────
class _DoneScreen extends StatelessWidget {
  const _DoneScreen({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
          const Text('You\'ve finished all slides and quizzes.',
              style: TextStyle(fontSize: 14, color: AColors.textMuted)),
          const SizedBox(height: 24),
          AButton(label: 'Back to Catalog', icon: Icons.library_books_rounded,
              onPressed: onBack),
        ]),
      ),
    );
  }
}
