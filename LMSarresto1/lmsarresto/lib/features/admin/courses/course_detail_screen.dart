import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/colors.dart';
import '../../../core/api/models.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/course_service.dart';
import '../../../core/api/video_service.dart';
import '../../../core/providers/library_provider.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_badge.dart';

class AdminCourseDetailScreen extends ConsumerStatefulWidget {
  const AdminCourseDetailScreen({super.key, required this.scriptId});
  final String scriptId;
  @override
  ConsumerState<AdminCourseDetailScreen> createState() => _State();
}

class _State extends ConsumerState<AdminCourseDetailScreen> {
  CourseScript? _script;
  bool _loading = true;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await CourseService.getScript(widget.scriptId);
      if (mounted) setState(() { _script = s; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _download() {
    final url = '${ApiClient.base}/api/v1/courses/library/${widget.scriptId}/download';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Course?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AColors.ink)),
        content: Text(
          'This will permanently remove "${_script?.title ?? 'this course'}" from the library.\n\nThis cannot be undone.',
          style: const TextStyle(fontSize: 14, color: AColors.textSecond, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AColors.red),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await CourseService.deleteScript(widget.scriptId);
      await ref.read(libraryProvider.notifier).refresh();
      if (mounted) context.go('/admin/courses');
    } catch (e) {
      if (mounted) setState(() { _deleting = false; _error = 'Delete failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _script == null) {
      return Center(child: Text('Error: $_error', style: const TextStyle(color: AColors.red)));
    }
    final s = _script!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
            if (s.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(s.description,
                  style: const TextStyle(fontSize: 14, color: AColors.textMuted)),
            ],
          ])),
          const SizedBox(width: 16),
          // Edit Script
          AButton(
            label: 'Edit Script',
            icon: Icons.edit_note_rounded,
            variant: AButtonVariant.ghost,
            onPressed: () => context.go('/admin/courses/${widget.scriptId}/script'),
          ),
          const SizedBox(width: 8),
          // Download JSON
          AButton(
            label: 'Download',
            icon: Icons.download_rounded,
            variant: AButtonVariant.ghost,
            onPressed: _download,
          ),
          const SizedBox(width: 8),
          // Delete
          AButton(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            variant: AButtonVariant.danger,
            loading: _deleting,
            onPressed: _confirmDelete,
          ),
        ]),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 12, color: AColors.red)),
        ],
        const SizedBox(height: 28),

        // ── Modules (standard) ────────────────────────────────────────
        if (!s.isCustom) ...s.modules.map((m) => _ModuleSection(m, widget.scriptId)),

        // ── Items (blueprint / custom) ────────────────────────────────
        if (s.isCustom) ...s.items.asMap().entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ItemCard(item: e.value, index: e.key, scriptId: widget.scriptId),
          ),
        ),
      ]),
    );
  }
}

// ── Module section ─────────────────────────────────────────────────────────────

class _ModuleSection extends StatelessWidget {
  const _ModuleSection(this.module, this.scriptId);
  final CourseModule module;
  final String scriptId;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Text('Module ${module.moduleNumber}: ${module.title}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AColors.ink)),
      ),
      ...module.lessons.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _LessonCard(l, scriptId, module.moduleNumber),
      )),
      const SizedBox(height: 8),
    ]);
  }
}

// ── Lesson card (standard courses) ────────────────────────────────────────────

class _LessonCard extends StatefulWidget {
  const _LessonCard(this.lesson, this.scriptId, this.moduleNumber);
  final CourseLesson lesson;
  final String scriptId;
  final int moduleNumber;
  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  bool _expanded = false;
  String _lang = 'en';
  String _style = 'animated_scene';
  String? _renderId;
  VideoRender? _render;
  bool _rendering = false;
  String _renderMsg = '';
  Timer? _pollTimer;
  List<VideoRender> _existingRenders = [];
  bool _loadingRenders = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _onExpand() async {
    if (_expanded) { setState(() => _expanded = false); return; }
    setState(() { _expanded = true; _loadingRenders = true; });
    try {
      final all = await VideoService.getScriptRenders(widget.scriptId);
      final lessonRef = 'module_${widget.moduleNumber}_lesson_${widget.lesson.lessonNumber}';
      if (mounted) {
        setState(() {
          _existingRenders = all.where((r) => r.lessonRef == lessonRef).toList();
          _loadingRenders = false;
          final done = _existingRenders.where((r) => r.isCompleted).toList();
          if (done.isNotEmpty) {
            _render = done.last; _renderId = done.last.renderId;
            _lang = done.last.lang; _style = done.last.style;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRenders = false);
    }
  }

  Future<void> _startRender() async {
    setState(() { _rendering = true; _renderMsg = 'Starting…'; _renderId = null; _render = null; });
    try {
      final rid = await VideoService.renderLesson(
        scriptId: widget.scriptId,
        moduleNumber: widget.moduleNumber,
        lessonNumber: widget.lesson.lessonNumber,
        lang: _lang, style: _style,
      );
      setState(() { _renderId = rid; _renderMsg = 'Processing…'; });
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    } catch (e) {
      setState(() { _rendering = false; _renderMsg = 'Error: $e'; });
    }
  }

  Future<void> _poll() async {
    if (_renderId == null) return;
    try {
      final r = await VideoService.getRenderStatus(_renderId!);
      if (mounted) {
        setState(() { _render = r; _renderMsg = r.status; });
        if (r.isDone) { _pollTimer?.cancel(); setState(() => _rendering = false); }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    return ACard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _onExpand,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: AColors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Center(child: Text('${l.lessonNumber}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.blue))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AColors.ink)),
                if (l.summary.isNotEmpty)
                  Text(l.summary,
                      style: const TextStyle(fontSize: 12, color: AColors.textMuted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const Icon(Icons.movie_creation_outlined, size: 14, color: AColors.textMuted),
              const SizedBox(width: 6),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AColors.textMuted),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (l.keyTakeaways.isNotEmpty) ...[
                const Text('Key Takeaways',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink)),
                const SizedBox(height: 6),
                ...l.keyTakeaways.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: AColors.amber)),
                    Expanded(child: Text(t,
                        style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
                  ]),
                )),
                const SizedBox(height: 16),
              ],
              if (_loadingRenders)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading renders…',
                        style: TextStyle(fontSize: 12, color: AColors.textMuted)),
                  ]),
                )
              else if (_existingRenders.isNotEmpty) ...[
                const Text('Previous Renders',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink)),
                const SizedBox(height: 8),
                ..._existingRenders.map((r) => _RenderRow(r)),
                const SizedBox(height: 16),
              ],
              _VideoPanel(
                lang: _lang, style: _style, rendering: _rendering,
                renderMsg: _renderMsg, render: _render, renderId: _renderId,
                onLangChange: (v) => setState(() => _lang = v),
                onStyleChange: (v) => setState(() => _style = v),
                onRender: _startRender,
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Item card (blueprint / custom courses) ─────────────────────────────────────

class _ItemCard extends StatefulWidget {
  const _ItemCard({required this.item, required this.index, required this.scriptId});
  final CourseItem item;
  final int index;
  final String scriptId;
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _expanded = false;
  String _lang = 'en';
  String _style = 'animated_scene';
  String? _renderId;
  VideoRender? _render;
  bool _rendering = false;
  String _renderMsg = '';
  Timer? _pollTimer;
  List<VideoRender> _existingRenders = [];
  bool _loadingRenders = false;

  bool get _renderable => widget.item.type == 'slide' || widget.item.type == 'closing_slide';

  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  Future<void> _onExpand() async {
    if (_expanded) { setState(() => _expanded = false); return; }
    setState(() { _expanded = true; _loadingRenders = _renderable; });
    if (!_renderable) return;
    try {
      final all = await VideoService.getScriptRenders(widget.scriptId);
      final lessonRef = 'item_${widget.index}';
      if (mounted) {
        setState(() {
          _existingRenders = all.where((r) => r.lessonRef == lessonRef).toList();
          _loadingRenders = false;
          final done = _existingRenders.where((r) => r.isCompleted).toList();
          if (done.isNotEmpty) {
            _render = done.last; _renderId = done.last.renderId;
            _lang = done.last.lang; _style = done.last.style;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRenders = false);
    }
  }

  Future<void> _startRender() async {
    setState(() { _rendering = true; _renderMsg = 'Starting…'; _renderId = null; _render = null; });
    try {
      final rid = await VideoService.renderItem(
        scriptId: widget.scriptId,
        itemIndex: widget.index,
        lang: _lang, style: _style,
      );
      setState(() { _renderId = rid; _renderMsg = 'Processing…'; });
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    } catch (e) {
      setState(() { _rendering = false; _renderMsg = 'Error: $e'; });
    }
  }

  Future<void> _poll() async {
    if (_renderId == null) return;
    try {
      final r = await VideoService.getRenderStatus(_renderId!);
      if (mounted) {
        setState(() { _render = r; _renderMsg = r.status; });
        if (r.isDone) { _pollTimer?.cancel(); setState(() => _rendering = false); }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isQuiz = item.type == 'quiz';

    return ACard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              ABadge(item.type,
                  variant: isQuiz ? ABadgeVariant.orange : ABadgeVariant.blue),
              const SizedBox(width: 12),
              Expanded(child: Text(item.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (_renderable) ...[
                const Icon(Icons.movie_creation_outlined, size: 14, color: AColors.textMuted),
                const SizedBox(width: 6),
              ],
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AColors.textMuted, size: 18),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Bullets
              if (item.bullets.isNotEmpty) ...[
                const Text('Slide Content',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink)),
                const SizedBox(height: 6),
                ...item.bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: AColors.amber)),
                    Expanded(child: Text(b,
                        style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
                  ]),
                )),
                const SizedBox(height: 16),
              ],
              if (isQuiz)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AColors.amberSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Icon(Icons.quiz_outlined, size: 16, color: AColors.orange),
                    SizedBox(width: 8),
                    Text('Quiz items cannot be rendered as video.',
                        style: TextStyle(fontSize: 12, color: AColors.orange)),
                  ]),
                ),
              if (_renderable) ...[
                if (_loadingRenders)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Loading renders…',
                          style: TextStyle(fontSize: 12, color: AColors.textMuted)),
                    ]),
                  )
                else if (_existingRenders.isNotEmpty) ...[
                  const Text('Previous Renders',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink)),
                  const SizedBox(height: 8),
                  ..._existingRenders.map((r) => _RenderRow(r)),
                  const SizedBox(height: 16),
                ],
                _VideoPanel(
                  lang: _lang, style: _style, rendering: _rendering,
                  renderMsg: _renderMsg, render: _render, renderId: _renderId,
                  onLangChange: (v) => setState(() => _lang = v),
                  onStyleChange: (v) => setState(() => _style = v),
                  onRender: _startRender,
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Shared: existing render row ────────────────────────────────────────────────

class _RenderRow extends StatelessWidget {
  const _RenderRow(this.r);
  final VideoRender r;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        ABadge(r.status, variant: statusVariant(r.status)),
        const SizedBox(width: 8),
        Text(r.lang.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AColors.textSecond)),
        const SizedBox(width: 6),
        Text('· ${r.style}', style: const TextStyle(fontSize: 12, color: AColors.textMuted)),
        const Spacer(),
        if (r.isCompleted)
          AButton(
            label: 'Download MP4',
            icon: Icons.download_rounded,
            variant: AButtonVariant.ghost,
            size: AButtonSize.sm,
            onPressed: () => launchUrl(Uri.parse(VideoService.downloadUrl(r.renderId)),
                mode: LaunchMode.externalApplication),
          ),
      ]),
    );
  }
}

// ── Shared: video render panel ─────────────────────────────────────────────────

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({
    required this.lang, required this.style, required this.rendering,
    required this.renderMsg, required this.render, required this.renderId,
    required this.onLangChange, required this.onStyleChange, required this.onRender,
  });
  final String lang, style, renderMsg;
  final bool rendering;
  final VideoRender? render;
  final String? renderId;
  final ValueChanged<String> onLangChange, onStyleChange;
  final VoidCallback onRender;

  static const _langs = {
    'en': '🇺🇸 English', 'en-in': '🇮🇳 English (India)',
    'hi': '🇮🇳 Hindi', 'ta': '🇮🇳 Tamil', 'te': '🇮🇳 Telugu',
    'bn': '🇮🇳 Bengali', 'gu': '🇮🇳 Gujarati', 'kn': '🇮🇳 Kannada',
    'ml': '🇮🇳 Malayalam', 'mr': '🇮🇳 Marathi', 'pa': '🇮🇳 Punjabi',
    'od': '🇮🇳 Odia', 'es': '🇪🇸 Spanish', 'fr': '🇫🇷 French',
    'de': '🇩🇪 German', 'ar': '🇸🇦 Arabic', 'zh': '🇨🇳 Chinese',
    'ja': '🇯🇵 Japanese', 'ko': '🇰🇷 Korean', 'pt': '🇧🇷 Portuguese',
  };
  static const _styles = {
    'animated_scene':    'HeyGen — Animated Scene',
    'whiteboard_doodle': 'HeyGen — Whiteboard Doodle',
    'hybrid':            'HeyGen — Hybrid',
    'modern':            'Free — Modern',
    'flatcolor':         'Free — Flat Color',
    'whiteboard':        'Free — Whiteboard',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.movie_creation_outlined, size: 16, color: AColors.textMuted),
          SizedBox(width: 6),
          Text('Generate Video',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Language: ', style: TextStyle(fontSize: 12, color: AColors.textMuted)),
          DropdownButton<String>(
            value: lang, isDense: true, underline: const SizedBox(),
            items: _langs.entries.map((e) => DropdownMenuItem(
                value: e.key, child: Text(e.value,
                    style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: rendering ? null : (v) { if (v != null) onLangChange(v); },
          ),
          const SizedBox(width: 16),
          const Text('Style: ', style: TextStyle(fontSize: 12, color: AColors.textMuted)),
          DropdownButton<String>(
            value: style, isDense: true, underline: const SizedBox(),
            items: _styles.entries.map((e) => DropdownMenuItem(
                value: e.key, child: Text(e.value,
                    style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: rendering ? null : (v) { if (v != null) onStyleChange(v); },
          ),
        ]),
        const SizedBox(height: 10),
        if (rendering)
          const Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Rendering…', style: TextStyle(fontSize: 12, color: AColors.textMuted)),
          ])
        else ...[
          Row(children: [
            AButton(
              label: 'Render Video',
              icon: Icons.play_arrow_rounded,
              variant: AButtonVariant.dark,
              size: AButtonSize.sm,
              onPressed: onRender,
            ),
            if (render?.isCompleted == true) ...[
              const SizedBox(width: 8),
              AButton(
                label: 'Download MP4',
                icon: Icons.download_rounded,
                variant: AButtonVariant.ghost,
                size: AButtonSize.sm,
                onPressed: () => launchUrl(
                    Uri.parse(VideoService.downloadUrl(renderId!)),
                    mode: LaunchMode.externalApplication),
              ),
            ],
          ]),
          if (renderMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(renderMsg, style: TextStyle(
                  fontSize: 11,
                  color: render?.isFailed == true ? AColors.red : AColors.textMuted)),
            ),
        ],
      ]),
    );
  }
}
