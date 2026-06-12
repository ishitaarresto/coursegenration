import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/api/course_service.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_card.dart';

/// Full-screen script editor. Loads the raw JSON, presents every editable
/// field inline, and PATCHes back on save.
class ScriptEditorScreen extends StatefulWidget {
  const ScriptEditorScreen({super.key, required this.scriptId});
  final String scriptId;
  @override
  State<ScriptEditorScreen> createState() => _ScriptEditorState();
}

class _ScriptEditorState extends State<ScriptEditorScreen> {
  // ── state ─────────────────────────────────────────────────────────
  bool _loading = true;
  bool _saving  = false;
  String? _error;
  String? _savedMsg;

  // ── raw JSON kept in memory ────────────────────────────────────────
  Map<String, dynamic>? _script;   // course_script portion

  // ── top-level controllers ──────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _objCtrl   = TextEditingController(); // objectives, one per line

  // ── module/lesson controllers (standard courses) ───────────────────
  // indexed as _modCtrls[m] and _lesCtrls[m][l]
  final List<_ModCtrl>            _modCtrls = [];
  final List<List<_LessonCtrl>>   _lesCtrls = [];

  // ── item controllers (custom/blueprint courses) ────────────────────
  final List<_ItemCtrl> _itemCtrls = [];

  bool get _isCustom {
    final items = _script?['items'] as List?;
    return items != null && items.isNotEmpty;
  }

  // ── load ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await CourseService.getRawScript(widget.scriptId);
      final script = raw['course_script'] as Map<String, dynamic>? ?? {};
      _script = script;
      _buildControllers(script);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _buildControllers(Map<String, dynamic> script) {
    _titleCtrl.text = (script['title'] ?? script['course_title'] ?? '') as String;
    _descCtrl.text  = (script['description'] ?? '') as String;
    final objs = script['learning_objectives'] as List? ?? [];
    _objCtrl.text   = objs.join('\n');

    _modCtrls.clear();
    _lesCtrls.clear();
    _itemCtrls.clear();

    if (_isCustom) {
      for (final item in script['items'] as List) {
        final m = item as Map<String, dynamic>;
        _itemCtrls.add(_ItemCtrl.from(m));
      }
    } else {
      for (final mod in script['modules'] as List? ?? []) {
        final m = mod as Map<String, dynamic>;
        _modCtrls.add(_ModCtrl(title: TextEditingController(text: m['module_title'] as String? ?? '')));
        final lessonCtrls = <_LessonCtrl>[];
        for (final les in m['lessons'] as List? ?? []) {
          final l = les as Map<String, dynamic>;
          lessonCtrls.add(_LessonCtrl.from(l));
        }
        _lesCtrls.add(lessonCtrls);
      }
    }
  }

  // ── save ──────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() { _saving = true; _savedMsg = null; _error = null; });
    try {
      final updated = _buildUpdatedScript();
      await CourseService.saveScript(
        widget.scriptId,
        updated,
        courseTitle: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      );
      if (mounted) setState(() { _saving = false; _savedMsg = 'Saved successfully.'; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  Map<String, dynamic> _buildUpdatedScript() {
    final base = Map<String, dynamic>.from(_script!);
    base['title'] = _titleCtrl.text.trim();
    if (base.containsKey('course_title')) {
      base['course_title'] = _titleCtrl.text.trim();
    }
    base['description'] = _descCtrl.text.trim();
    final objLines = _objCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    base['learning_objectives'] = objLines;

    if (_isCustom) {
      final origItems = base['items'] as List;
      base['items'] = List.generate(origItems.length, (i) {
        final orig = Map<String, dynamic>.from(origItems[i] as Map<String, dynamic>);
        if (i < _itemCtrls.length) {
          _itemCtrls[i].writeTo(orig);
        }
        return orig;
      });
    } else {
      final origMods = base['modules'] as List? ?? [];
      base['modules'] = List.generate(origMods.length, (m) {
        final origMod = Map<String, dynamic>.from(origMods[m] as Map<String, dynamic>);
        if (m < _modCtrls.length) {
          origMod['module_title'] = _modCtrls[m].title.text.trim();
        }
        final origLessons = origMod['lessons'] as List? ?? [];
        origMod['lessons'] = List.generate(origLessons.length, (l) {
          final origLes = Map<String, dynamic>.from(origLessons[l] as Map<String, dynamic>);
          if (m < _lesCtrls.length && l < _lesCtrls[m].length) {
            _lesCtrls[m][l].writeTo(origLes);
          }
          return origLes;
        });
        return origMod;
      });
    }

    return base;
  }

  // ── dispose ────────────────────────────────────────────────────────
  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _objCtrl.dispose();
    for (final c in _modCtrls) { c.dispose(); }
    for (final row in _lesCtrls) { for (final c in row) { c.dispose(); } }
    for (final c in _itemCtrls) { c.dispose(); }
    super.dispose();
  }

  // ── build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _script == null) {
      return Center(child: Text(_error!, style: const TextStyle(color: AColors.red)));
    }

    return Column(children: [
      // ── sticky header ──────────────────────────────────────────────
      _Header(
        saving: _saving,
        savedMsg: _savedMsg,
        error: _error,
        onSave: _save,
      ),
      const Divider(height: 1),

      // ── scrollable body ────────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Top-level fields ────────────────────────────────────
            ACard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _SectionLabel('Course Info'),
                const SizedBox(height: 16),
                _FieldGroup('Course Title', _titleCtrl, maxLines: 1),
                const SizedBox(height: 14),
                _FieldGroup('Description', _descCtrl, maxLines: 3),
                const SizedBox(height: 14),
                _FieldGroup(
                  'Learning Objectives',
                  _objCtrl,
                  maxLines: 6,
                  hint: 'One objective per line',
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Modules / Lessons ────────────────────────────────────
            if (!_isCustom) ..._buildModuleSections(),

            // ── Items (custom/blueprint) ─────────────────────────────
            if (_isCustom) ..._buildItemSections(),
          ]),
        ),
      ),
    ]);
  }

  List<Widget> _buildModuleSections() {
    final origMods = _script!['modules'] as List? ?? [];
    return List.generate(origMods.length, (m) {
      final origMod = origMods[m] as Map<String, dynamic>;
      final origLessons = origMod['lessons'] as List? ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: ACard(
          padding: EdgeInsets.zero,
          child: _ModuleSection(
            modIndex: m,
            modCtrl: _modCtrls[m],
            lessonCtrls: m < _lesCtrls.length ? _lesCtrls[m] : [],
            lessonCount: origLessons.length,
          ),
        ),
      );
    });
  }

  List<Widget> _buildItemSections() {
    final origItems = _script!['items'] as List? ?? [];
    return [
      const _SectionLabel('Slides & Items'),
      const SizedBox(height: 12),
      ...List.generate(origItems.length, (i) {
        final item = origItems[i] as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ItemSection(
            index: i,
            type: item['type'] as String? ?? 'slide',
            ctrl: i < _itemCtrls.length ? _itemCtrls[i] : _ItemCtrl.from(item),
          ),
        );
      }),
    ];
  }
}

// ── Module section ─────────────────────────────────────────────────────────────

class _ModuleSection extends StatefulWidget {
  const _ModuleSection({
    required this.modIndex, required this.modCtrl,
    required this.lessonCtrls, required this.lessonCount,
  });
  final int modIndex;
  final _ModCtrl modCtrl;
  final List<_LessonCtrl> lessonCtrls;
  final int lessonCount;
  @override
  State<_ModuleSection> createState() => _ModuleSectionState();
}

class _ModuleSectionState extends State<_ModuleSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Module header
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: AColors.ink, borderRadius: BorderRadius.circular(6)),
              child: Center(child: Text('M${widget.modIndex + 1}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.modCtrl.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.ink),
                decoration: const InputDecoration(
                  border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                  hintText: 'Module title',
                ),
                onTap: () {}, // prevent collapse on field tap
              ),
            ),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AColors.textMuted),
          ]),
        ),
      ),

      if (_expanded) ...[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(widget.lessonCtrls.length, (l) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _LessonSection(
                modIndex: widget.modIndex,
                lessonIndex: l,
                ctrl: widget.lessonCtrls[l],
              ),
            )),
          ),
        ),
      ],
    ]);
  }
}

// ── Lesson section ─────────────────────────────────────────────────────────────

class _LessonSection extends StatefulWidget {
  const _LessonSection({required this.modIndex, required this.lessonIndex, required this.ctrl});
  final int modIndex, lessonIndex;
  final _LessonCtrl ctrl;
  @override
  State<_LessonSection> createState() => _LessonSectionState();
}

class _LessonSectionState extends State<_LessonSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.ctrl;
    return Container(
      decoration: BoxDecoration(
        color: AColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Lesson header row
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: AColors.blue.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Center(child: Text('${widget.lessonIndex + 1}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AColors.blue))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: l.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
                  decoration: const InputDecoration(
                    border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    hintText: 'Lesson title',
                  ),
                ),
              ),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AColors.textMuted, size: 18),
            ]),
          ),
        ),

        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FieldGroup('Summary', l.summary, maxLines: 2),
              const SizedBox(height: 14),
              _FieldGroup('Narration Script', l.narration, maxLines: 10,
                  hint: 'Full spoken narration for this lesson…'),
              const SizedBox(height: 14),
              _FieldGroup('Slide Bullets', l.bullets, maxLines: 6,
                  hint: 'One bullet per line'),
              const SizedBox(height: 14),
              _FieldGroup('Key Takeaways', l.takeaways, maxLines: 4,
                  hint: 'One takeaway per line'),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Item section (custom/blueprint) ───────────────────────────────────────────

class _ItemSection extends StatefulWidget {
  const _ItemSection({required this.index, required this.type, required this.ctrl});
  final int index;
  final String type;
  final _ItemCtrl ctrl;
  @override
  State<_ItemSection> createState() => _ItemSectionState();
}

class _ItemSectionState extends State<_ItemSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isQuiz = widget.type == 'quiz';
    return ACard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isQuiz ? AColors.orange.withValues(alpha: 0.12) : AColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(widget.type.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: isQuiz ? AColors.orange : AColors.blue)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.ctrl.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
                  decoration: const InputDecoration(
                    border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    hintText: 'Item title',
                  ),
                ),
              ),
              Text('Item ${widget.index + 1}',
                  style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AColors.textMuted, size: 18),
            ]),
          ),
        ),

        if (_expanded && !isQuiz) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FieldGroup('Narration', widget.ctrl.narration, maxLines: 8,
                  hint: 'Full spoken narration for this slide…'),
              const SizedBox(height: 14),
              _FieldGroup('Bullets', widget.ctrl.bullets, maxLines: 5,
                  hint: 'One bullet per line'),
              const SizedBox(height: 14),
              _FieldGroup('Takeaway', widget.ctrl.takeaway, maxLines: 2),
            ]),
          ),
        ],
        if (_expanded && isQuiz) ...[
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Quiz items are not editable here.',
                style: TextStyle(fontSize: 12, color: AColors.textMuted)),
          ),
        ],
      ]),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.saving, required this.savedMsg, required this.error, required this.onSave});
  final bool saving;
  final String? savedMsg, error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      child: Row(children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Script Editor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AColors.ink)),
          Text('Edit narration, bullets and titles — then save.',
              style: TextStyle(fontSize: 12, color: AColors.textMuted)),
        ]),
        const Spacer(),
        if (savedMsg != null)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: AColors.green, size: 16),
              const SizedBox(width: 6),
              Text(savedMsg!, style: const TextStyle(fontSize: 13, color: AColors.green)),
            ]),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Text('Error: $error',
                style: const TextStyle(fontSize: 12, color: AColors.red),
                maxLines: 2),
          ),
        AButton(
          label: 'Save Changes',
          icon: Icons.save_rounded,
          loading: saving,
          onPressed: onSave,
        ),
      ]),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.ink));
}

class _FieldGroup extends StatelessWidget {
  const _FieldGroup(this.label, this.controller, {this.maxLines = 1, this.hint});
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: AColors.textSecond)),
      const SizedBox(height: 5),
      TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13, color: AColors.ink, height: 1.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AColors.textMuted2, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: AColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.amber, width: 2),
          ),
        ),
      ),
    ]);
  }
}

// ── Controller data classes ────────────────────────────────────────────────────

class _ModCtrl {
  final TextEditingController title;
  _ModCtrl({required this.title});
  void dispose() => title.dispose();
}

class _LessonCtrl {
  final TextEditingController title, summary, narration, bullets, takeaways;
  _LessonCtrl({
    required this.title, required this.summary,
    required this.narration, required this.bullets, required this.takeaways,
  });

  factory _LessonCtrl.from(Map<String, dynamic> l) {
    final slide = l['slide_content'];
    List<String> buls;
    if (slide is Map) {
      buls = List<String>.from(slide['bullets'] as List? ?? []);
    } else {
      buls = List<String>.from(l['slide_bullets'] as List? ?? []);
    }
    return _LessonCtrl(
      title:     TextEditingController(text: l['lesson_title'] as String? ?? l['title'] as String? ?? ''),
      summary:   TextEditingController(text: l['summary'] as String? ?? ''),
      narration: TextEditingController(text: l['narration_script'] as String? ?? l['narration'] as String? ?? ''),
      bullets:   TextEditingController(text: buls.join('\n')),
      takeaways: TextEditingController(text: (List<String>.from(l['key_takeaways'] as List? ?? [])).join('\n')),
    );
  }

  void writeTo(Map<String, dynamic> l) {
    l['lesson_title'] = title.text.trim();
    l['summary']      = summary.text.trim();
    l['narration_script'] = narration.text.trim();
    l['narration']        = narration.text.trim();
    final buls = bullets.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final takes = takeaways.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Patch slide_content bullets in-place
    final slide = l['slide_content'];
    if (slide is Map) {
      (slide as Map<String, dynamic>)['bullets'] = buls;
    } else {
      l['slide_bullets'] = buls;
    }
    l['key_takeaways'] = takes;
  }

  void dispose() {
    title.dispose(); summary.dispose(); narration.dispose();
    bullets.dispose(); takeaways.dispose();
  }
}

class _ItemCtrl {
  final TextEditingController title, narration, bullets, takeaway;
  _ItemCtrl({required this.title, required this.narration, required this.bullets, required this.takeaway});

  factory _ItemCtrl.from(Map<String, dynamic> i) => _ItemCtrl(
    title:     TextEditingController(text: i['title'] as String? ?? ''),
    narration: TextEditingController(text: i['narration'] as String? ?? i['narration_script'] as String? ?? ''),
    bullets:   TextEditingController(text: (List<String>.from(i['bullets'] as List? ?? [])).join('\n')),
    takeaway:  TextEditingController(text: i['takeaway'] as String? ?? ''),
  );

  void writeTo(Map<String, dynamic> i) {
    i['title']     = title.text.trim();
    i['narration'] = narration.text.trim();
    i['bullets']   = bullets.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    i['takeaway']  = takeaway.text.trim();
  }

  void dispose() { title.dispose(); narration.dispose(); bullets.dispose(); takeaway.dispose(); }
}
