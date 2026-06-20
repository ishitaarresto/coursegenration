import 'package:flutter/material.dart';
import '../../../core/services/course_service.dart';
import '../../../core/services/video_service.dart';

class ScriptReviewDialog extends StatefulWidget {
  final String scriptId;
  final String lessonTitle;
  final String lessonRef;
  final Map<String, dynamic> fullCourseScript;
  final int? itemIndex;
  final int? moduleNumber;
  final int? lessonNumber;
  final String lang;
  final String style;
  final String voice;
  final VoidCallback? onRenderStarted;

  const ScriptReviewDialog({
    super.key,
    required this.scriptId,
    required this.lessonTitle,
    required this.lessonRef,
    required this.fullCourseScript,
    this.itemIndex,
    this.moduleNumber,
    this.lessonNumber,
    this.lang = 'en',
    required this.style,
    required this.voice,
    this.onRenderStarted,
  });

  @override
  State<ScriptReviewDialog> createState() => _ScriptReviewDialogState();
}

class _ScriptReviewDialogState extends State<ScriptReviewDialog> {
  bool _editing = false;
  bool _isSaving = false;
  bool _isRendering = false;

  late TextEditingController _narrationCtrl;
  late List<TextEditingController> _bulletCtrls;
  late TextEditingController _takeawayCtrl;

  String _origNarration = '';
  List<String> _origBullets = [];
  String _origTakeaway = '';

  @override
  void initState() {
    super.initState();
    final (narration, bullets, takeaway) = _extractContent();
    _origNarration = narration;
    _origBullets = List.from(bullets);
    _origTakeaway = takeaway;
    _narrationCtrl = TextEditingController(text: narration);
    _bulletCtrls = bullets.map((b) => TextEditingController(text: b)).toList();
    _takeawayCtrl = TextEditingController(text: takeaway);
  }

  @override
  void dispose() {
    _narrationCtrl.dispose();
    for (final c in _bulletCtrls) {
      c.dispose();
    }
    _takeawayCtrl.dispose();
    super.dispose();
  }

  (String, List<String>, String) _extractContent() {
    if (widget.itemIndex != null) {
      final items = widget.fullCourseScript['items'] as List? ?? [];
      if (widget.itemIndex! >= items.length) return ('', [], '');
      final item = items[widget.itemIndex!] as Map<String, dynamic>;
      return (
        item['narration'] as String? ?? '',
        (item['bullets'] as List? ?? []).cast<String>(),
        item['takeaway'] as String? ?? '',
      );
    }
    final modules = widget.fullCourseScript['modules'] as List? ?? [];
    for (final m in modules) {
      final mod = m as Map<String, dynamic>;
      if ((mod['module_number'] as int?) == widget.moduleNumber) {
        for (final l in (mod['lessons'] as List? ?? [])) {
          final les = l as Map<String, dynamic>;
          if ((les['lesson_number'] as int?) == widget.lessonNumber) {
            final slide = les['slide_content'] as Map<String, dynamic>? ?? {};
            return (
              les['narration_script'] as String? ?? '',
              (slide['bullets'] as List? ?? []).cast<String>(),
              les['summary'] as String? ?? '',
            );
          }
        }
      }
    }
    return ('', [], '');
  }

  bool get _hasChanges {
    if (_narrationCtrl.text != _origNarration) return true;
    final current = _bulletCtrls.map((c) => c.text).toList();
    if (current.length != _origBullets.length) return true;
    for (int i = 0; i < current.length; i++) {
      if (current[i] != _origBullets[i]) return true;
    }
    return _takeawayCtrl.text != _origTakeaway;
  }

  Map<String, dynamic> _buildUpdatedScript() {
    final newNarration = _narrationCtrl.text.trim();
    final newBullets = _bulletCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final newTakeaway = _takeawayCtrl.text.trim();

    if (widget.itemIndex != null) {
      final items = (widget.fullCourseScript['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      items[widget.itemIndex!] = {
        ...items[widget.itemIndex!],
        'narration': newNarration,
        'bullets': newBullets,
        'takeaway': newTakeaway,
      };
      return {...widget.fullCourseScript, 'items': items};
    }

    final modules = (widget.fullCourseScript['modules'] as List).map((m) {
      final mod = Map<String, dynamic>.from(m as Map);
      if ((mod['module_number'] as int?) == widget.moduleNumber) {
        final lessons = (mod['lessons'] as List).map((l) {
          final les = Map<String, dynamic>.from(l as Map);
          if ((les['lesson_number'] as int?) == widget.lessonNumber) {
            final slide =
                Map<String, dynamic>.from(les['slide_content'] as Map? ?? {});
            slide['bullets'] = newBullets;
            les['narration_script'] = newNarration;
            les['slide_content'] = slide;
            les['summary'] = newTakeaway;
          }
          return les;
        }).toList();
        mod['lessons'] = lessons;
      }
      return mod;
    }).toList();

    return {...widget.fullCourseScript, 'modules': modules};
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final updated = _buildUpdatedScript();
      await CourseService.updateCourseScript(widget.scriptId, updated);
      _origNarration = _narrationCtrl.text;
      _origBullets = _bulletCtrls.map((c) => c.text).toList();
      _origTakeaway = _takeawayCtrl.text;
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _editing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script saved'),
          backgroundColor: Color(0xFF1F8A5B),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _onGenerateVideo() async {
    if (_hasChanges) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'Unsaved Changes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'You have unsaved edits to the script.\nSave them before generating the video?',
            style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'render_only'),
              child: const Text('Render Without Saving'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC2410C)),
              onPressed: () => Navigator.pop(ctx, 'save_render'),
              child: const Text('Save & Generate'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null || choice == 'cancel') return;
      if (choice == 'save_render') {
        await _save();
        if (!mounted || _isSaving) return;
      }
    }
    await _doRender();
  }

  Future<void> _doRender() async {
    setState(() => _isRendering = true);
    try {
      await VideoService.renderLesson(
        widget.scriptId,
        moduleNumber: widget.moduleNumber,
        lessonNumber: widget.lessonNumber,
        itemIndex: widget.itemIndex,
        lang: widget.lang,
        style: widget.style,
        voice: widget.voice,
      );
      widget.onRenderStarted?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRendering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Render failed: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(
                height: 1, thickness: 1, color: Color(0xFFE8E4DE)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNarrationSection(),
                    const SizedBox(height: 20),
                    _buildBulletsSection(),
                    const SizedBox(height: 20),
                    _buildTakeawaySection(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            const Divider(
                height: 1, thickness: 1, color: Color(0xFFE8E4DE)),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1B1B1D),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.description_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.lessonTitle,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B1B1D)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _Pill(
                      label: widget.lessonRef,
                      color: const Color(0xFF6B6B6B),
                      bg: const Color(0xFFF0EFED),
                    ),
                    const SizedBox(width: 5),
                    _Pill(
                      label: widget.style,
                      color: const Color(0xFFC2410C),
                      bg: const Color(0xFFFFF3ED),
                    ),
                    const SizedBox(width: 5),
                    _Pill(
                      label: widget.voice,
                      color: const Color(0xFF1F8A5B),
                      bg: const Color(0xFFEEF7F3),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(
              _editing ? Icons.edit_off_rounded : Icons.edit_rounded,
              size: 15,
            ),
            label: Text(_editing ? 'Done' : 'Edit'),
            style: TextButton.styleFrom(
              foregroundColor: _editing
                  ? const Color(0xFFC2410C)
                  : const Color(0xFF1B1B1D),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: const Color(0xFF9B9B9B),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrationSection() {
    return _Section(
      label: 'Narration Script',
      icon: Icons.mic_rounded,
      child: _editing
          ? TextField(
              controller: _narrationCtrl,
              maxLines: null,
              minLines: 6,
              style: const TextStyle(
                  fontSize: 13, height: 1.65, color: Color(0xFF1B1B1D)),
              decoration: _inputDecoration('Enter narration script…'),
            )
          : _readBox(
              _narrationCtrl.text.isEmpty
                  ? 'No narration script.'
                  : _narrationCtrl.text,
              minLines: 4,
            ),
    );
  }

  Widget _buildBulletsSection() {
    return _Section(
      label: 'Slide Bullets',
      icon: Icons.format_list_bulleted_rounded,
      child: _editing
          ? Column(
              children: [
                ...List.generate(_bulletCtrls.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Text('•  ',
                            style: TextStyle(
                                color: Color(0xFFC2410C), fontSize: 16)),
                        Expanded(
                          child: TextField(
                            controller: _bulletCtrls[i],
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF1B1B1D)),
                            decoration:
                                _inputDecoration('Bullet point…'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: () => setState(() {
                            _bulletCtrls[i].dispose();
                            _bulletCtrls.removeAt(i);
                          }),
                          icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 18),
                          color: const Color(0xFFDC2626),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                        () => _bulletCtrls.add(TextEditingController())),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Bullet'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC2410C),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            )
          : _bulletCtrls.isEmpty || _bulletCtrls.every((c) => c.text.isEmpty)
              ? const Text('No bullets.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B)))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _bulletCtrls
                      .where((c) => c.text.isNotEmpty)
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Icon(Icons.circle,
                                    size: 5, color: Color(0xFFC2410C)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(c.text,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.55,
                                        color: Color(0xFF1B1B1D))),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
    );
  }

  Widget _buildTakeawaySection() {
    return _Section(
      label: 'Key Takeaway / Summary',
      icon: Icons.lightbulb_rounded,
      child: _editing
          ? TextField(
              controller: _takeawayCtrl,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: Color(0xFF1B1B1D)),
              decoration: _inputDecoration('Enter key takeaway…'),
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFC2410C).withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_rounded,
                      size: 15, color: Color(0xFFC2410C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _takeawayCtrl.text.isEmpty
                          ? 'No takeaway.'
                          : _takeawayCtrl.text,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF1B1B1D)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          if (_hasChanges) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text('Unsaved changes',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF9B9B9B))),
          ],
          const Spacer(),
          if (_hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: OutlinedButton(
                onPressed: _isSaving ? null : _save,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1B1B1D)),
                  foregroundColor: const Color(0xFF1B1B1D),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1B1B1D)),
                      )
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          FilledButton.icon(
            onPressed: _isRendering ? null : _onGenerateVideo,
            icon: _isRendering
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_circle_rounded, size: 16),
            label: const Text('Generate Video',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC2410C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFFAF9F7),
      hintText: hint,
      hintStyle:
          const TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE8E4DE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE8E4DE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide:
            const BorderSide(color: Color(0xFFC2410C), width: 1.5),
      ),
    );
  }

  Widget _readBox(String text, {int minLines = 2}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E4DE)),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 13, height: 1.65, color: Color(0xFF1B1B1D)),
      ),
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;

  const _Section({
    required this.label,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF9B9B9B)),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF9B9B9B)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// ── Pill badge ────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _Pill({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
