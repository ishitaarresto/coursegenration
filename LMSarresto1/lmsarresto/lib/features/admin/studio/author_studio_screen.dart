import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/document_service.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/colors.dart';

// 17 languages supported by the compat render pipeline
const _kLangs = {
  'en': 'English (US)',
  'en-in': 'English (India)',
  'hi': 'Hindi',
  'ta': 'Tamil',
  'te': 'Telugu',
  'bn': 'Bengali',
  'mr': 'Marathi',
  'gu': 'Gujarati',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'pa': 'Punjabi',
  'or': 'Odia',
  'as': 'Assamese',
  'ur': 'Urdu',
  'fr': 'French',
  'es': 'Spanish',
  'de': 'German',
};

const _kStyles = {
  'animated_scene': 'Animated Scene',
  'whiteboard_doodle': 'Whiteboard Doodle',
  'hybrid': 'Hybrid',
  'modern': 'Modern (Free)',
  'flatcolor': 'Flat Color (Free)',
  'whiteboard': 'Whiteboard (Free)',
};

const _kHeygenStyles = {'animated_scene', 'whiteboard_doodle', 'hybrid'};

const _kEconomies = {'lean': 'Lean', 'standard': 'Standard', 'premium': 'Premium'};

// ── Screen ─────────────────────────────────────────────────────────────────────

class AuthorStudioScreen extends StatefulWidget {
  const AuthorStudioScreen({super.key});

  @override
  State<AuthorStudioScreen> createState() => _AuthorStudioScreenState();
}

class _AuthorStudioScreenState extends State<AuthorStudioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: AColors.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Author Studio',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: AColors.ink)),
              const SizedBox(height: 2),
              const Text('Generate, browse and manage course content',
                  style: TextStyle(fontSize: 13, color: AColors.textMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tab,
            labelColor: AColors.blue,
            unselectedLabelColor: AColors.textMuted,
            indicatorColor: AColors.blue,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            dividerColor: AColors.cardBorder,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(text: 'Generate'),
              Tab(text: 'Library'),
              Tab(text: 'Documents'),
            ],
          ),
        ]),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            _GenerateTab(),
            _LibraryTab(),
            _DocumentsTab(),
          ],
        ),
      ),
    ]);
  }
}

// ── Generate Tab ───────────────────────────────────────────────────────────────

class _GenerateTab extends StatefulWidget {
  const _GenerateTab();

  @override
  State<_GenerateTab> createState() => _GenerateTabState();
}

class _GenerateTabState extends State<_GenerateTab> {
  final _textCtrl = TextEditingController();
  final _jsonCtrl = TextEditingController();
  String _genMode = 'text';
  String _lang = 'en';
  String _courseMode = 'detailed';
  bool _generating = false;
  String _step = '';
  double _progress = 0;
  Map<String, dynamic>? _course;
  int? _courseId;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final content =
        _genMode == 'text' ? _textCtrl.text.trim() : _jsonCtrl.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _generating = true;
      _step = 'Starting generation…';
      _progress = 0.05;
      _course = null;
      _error = null;
    });

    try {
      final genData = await ApiClient.post('/api/courses/generate', {
        'content_text': content,
        'mode': _courseMode,
        'languages': [_lang],
      });
      final id = (genData as Map<String, dynamic>)['id'] as int;
      setState(() {
        _courseId = id;
        _step = 'Generating course…';
        _progress = 0.2;
      });

      while (true) {
        await Future.delayed(const Duration(seconds: 2));
        final job = await ApiClient.get('/api/jobs/$id') as Map<String, dynamic>;
        final status = job['status'] as String? ?? '';
        final pct = (job['progress'] as num?)?.toDouble() ?? 0;
        setState(() {
          _step = job['step'] as String? ?? 'Processing…';
          _progress = 0.2 + pct * 0.7;
        });
        if (['done', 'completed', 'success'].contains(status)) break;
        if (['error', 'failed', 'failure'].contains(status)) {
          throw Exception(job['error'] ?? 'Generation failed');
        }
      }

      setState(() {
        _step = 'Loading course…';
        _progress = 0.95;
      });
      final courseData =
          await ApiClient.get('/api/courses/$id') as Map<String, dynamic>;
      setState(() {
        _course = courseData;
        _progress = 1.0;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 360,
        color: AColors.surface,
        child: _buildInputPanel(),
      ),
      const VerticalDivider(width: 1, color: AColors.cardBorder),
      Expanded(
        child: _course != null
            ? _CompatCourseView(
                course: _course!, courseId: _courseId!, genLang: _lang)
            : _buildEmptyRight(),
      ),
    ]);
  }

  Widget _buildInputPanel() {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        _ModeChip(
            label: 'From Text',
            active: _genMode == 'text',
            onTap: () => setState(() => _genMode = 'text')),
        const SizedBox(width: 8),
        _ModeChip(
            label: 'Import JSON',
            active: _genMode == 'json',
            onTap: () => setState(() => _genMode = 'json')),
      ]),
      const SizedBox(height: 16),
      Text(_genMode == 'text' ? 'Course Content' : 'Course JSON',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AColors.textSecond)),
      const SizedBox(height: 6),
      TextField(
        controller: _genMode == 'text' ? _textCtrl : _jsonCtrl,
        maxLines: 10,
        minLines: 8,
        decoration: _inputDec(_genMode == 'text'
            ? 'Paste your training material or topic outline…'
            : 'Paste your course JSON here…'),
        style: TextStyle(
            fontSize: _genMode == 'json' ? 12 : 13,
            fontFamily: _genMode == 'json' ? 'monospace' : null,
            color: AColors.ink),
      ),
      const SizedBox(height: 16),
      const Text('Language',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AColors.textSecond)),
      const SizedBox(height: 6),
      _buildDropdown(
          value: _lang,
          items: _kLangs,
          onChanged: (v) => setState(() => _lang = v)),
      const SizedBox(height: 12),
      const Text('Style',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AColors.textSecond)),
      const SizedBox(height: 6),
      Row(children: [
        _ModeChip(
            label: 'Detailed',
            active: _courseMode == 'detailed',
            onTap: () => setState(() => _courseMode = 'detailed')),
        const SizedBox(width: 8),
        _ModeChip(
            label: 'Blueprint',
            active: _courseMode == 'blueprint',
            onTap: () => setState(() => _courseMode = 'blueprint')),
      ]),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _generating ? null : _generate,
          style: ElevatedButton.styleFrom(
            backgroundColor: AColors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Generate Course',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),
      if (_generating) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(
            value: _progress,
            backgroundColor: AColors.blueSoft,
            color: AColors.blue),
        const SizedBox(height: 6),
        Text(_step,
            style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AColors.redSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AColors.red.withValues(alpha: 0.3))),
          child: Text(_error!,
              style: const TextStyle(fontSize: 12, color: AColors.red)),
        ),
      ],
    ]);
  }

  Widget _buildEmptyRight() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: AColors.blueSoft,
              borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.auto_awesome_rounded,
              color: AColors.blue, size: 32),
        ),
        const SizedBox(height: 16),
        const Text('Course will appear here',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AColors.ink)),
        const SizedBox(height: 4),
        const Text('Enter your content and click Generate',
            style: TextStyle(fontSize: 13, color: AColors.textMuted)),
      ]),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AColors.textMuted),
        filled: true,
        fillColor: AColors.bg,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.cardBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.cardBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.blue, width: 1.5)),
      );

  Widget _buildDropdown(
      {required String value,
      required Map<String, String> items,
      required void Function(String) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: AColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AColors.cardBorder)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AColors.ink),
          items: items.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ── Compat Course View ─────────────────────────────────────────────────────────

class _CompatCourseView extends StatelessWidget {
  const _CompatCourseView(
      {required this.course, required this.courseId, required this.genLang});

  final Map<String, dynamic> course;
  final int courseId;
  final String genLang;

  @override
  Widget build(BuildContext context) {
    final title = course['title'] as String? ?? 'Untitled Course';
    final description = course['description'] as String? ?? '';
    final modules = (course['modules'] as List?)
            ?.map((m) => m as Map<String, dynamic>)
            .toList() ??
        [];
    final totalLessons = modules.fold<int>(0,
        (s, m) => s + ((m['lessons'] as List?)?.length ?? 0));

    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(description,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
          const SizedBox(height: 12),
          Text('${modules.length} modules · $totalLessons lessons',
              style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
      ),
      const SizedBox(height: 16),
      for (int mi = 0; mi < modules.length; mi++) ...[
        _ModuleSection(
          module: modules[mi],
          moduleIndex: mi,
          courseId: courseId,
          genLang: genLang,
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _ModuleSection extends StatefulWidget {
  const _ModuleSection({
    required this.module,
    required this.moduleIndex,
    required this.courseId,
    required this.genLang,
  });

  final Map<String, dynamic> module;
  final int moduleIndex;
  final int courseId;
  final String genLang;

  @override
  State<_ModuleSection> createState() => _ModuleSectionState();
}

class _ModuleSectionState extends State<_ModuleSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final title =
        widget.module['title'] as String? ?? 'Module ${widget.moduleIndex + 1}';
    final lessons = (widget.module['lessons'] as List?)
            ?.map((l) => l as Map<String, dynamic>)
            .toList() ??
        [];

    return Container(
      decoration: BoxDecoration(
          color: AColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AColors.cardBorder)),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                    color: AColors.blueSoft, shape: BoxShape.circle),
                child: Center(
                  child: Text('${widget.moduleIndex + 1}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AColors.blue)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AColors.ink))),
              Text('${lessons.length} lessons',
                  style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: AColors.textMuted),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: AColors.cardBorder),
          for (int li = 0; li < lessons.length; li++)
            _LessonCard(
              lesson: lessons[li],
              lessonIndex: li,
              courseId: widget.courseId,
              genLang: widget.genLang,
            ),
        ],
      ]),
    );
  }
}

class _LessonCard extends StatefulWidget {
  const _LessonCard({
    required this.lesson,
    required this.lessonIndex,
    required this.courseId,
    required this.genLang,
  });

  final Map<String, dynamic> lesson;
  final int lessonIndex;
  final int courseId;
  final String genLang;

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  bool _videoOpen = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.lesson['title'] as String? ??
        'Lesson ${widget.lessonIndex + 1}';
    final summary = widget.lesson['summary'] as String? ?? '';
    final lessonId =
        (widget.lesson['id'] as num?)?.toInt() ?? widget.lessonIndex + 1;

    return Column(children: [
      if (widget.lessonIndex > 0)
        const Divider(height: 1, color: AColors.line),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  color: AColors.bg2,
                  borderRadius: BorderRadius.circular(4)),
              child: Center(
                child: Text('${widget.lessonIndex + 1}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AColors.textSecond)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AColors.ink))),
            GestureDetector(
              onTap: () => setState(() => _videoOpen = !_videoOpen),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color:
                        _videoOpen ? AColors.blueSoft : AColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _videoOpen
                            ? AColors.blue
                            : AColors.cardBorder)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.video_library_rounded,
                      size: 13,
                      color: _videoOpen
                          ? AColors.blue
                          : AColors.textMuted),
                  const SizedBox(width: 4),
                  Text(_videoOpen ? 'Hide' : 'Video',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _videoOpen
                              ? AColors.blue
                              : AColors.textMuted)),
                ]),
              ),
            ),
          ]),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(summary,
                style: const TextStyle(
                    fontSize: 12, color: AColors.textMuted, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (_videoOpen) ...[
            const SizedBox(height: 12),
            _CompatVideoPanel(
              courseId: widget.courseId,
              lessonId: lessonId,
              defaultLang: widget.genLang,
            ),
          ],
        ]),
      ),
    ]);
  }
}

// ── Compat Video Panel ─────────────────────────────────────────────────────────

class _CompatVideoPanel extends StatefulWidget {
  const _CompatVideoPanel({
    required this.courseId,
    required this.lessonId,
    required this.defaultLang,
  });

  final int courseId;
  final int lessonId;
  final String defaultLang;

  @override
  State<_CompatVideoPanel> createState() => _CompatVideoPanelState();
}

class _CompatVideoPanelState extends State<_CompatVideoPanel> {
  late String _lang;
  String _style = 'modern';
  String _economy = 'lean';
  bool _rendering = false;
  String _renderStep = '';
  bool _videoReady = false;
  String? _renderError;
  Map<String, dynamic>? _costData;
  bool _loadingCost = false;
  List<dynamic>? _quiz;

  @override
  void initState() {
    super.initState();
    _lang = widget.defaultLang;
  }

  bool get _isHeygen => _kHeygenStyles.contains(_style);

  Future<void> _loadCost() async {
    if (!_isHeygen) return;
    setState(() => _loadingCost = true);
    try {
      final data = await ApiClient.get(
          '/api/courses/${widget.courseId}/lessons/${widget.lessonId}/cost?economy=$_economy');
      if (mounted) setState(() => _costData = data as Map<String, dynamic>);
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingCost = false);
    }
  }

  Future<void> _render() async {
    setState(() {
      _rendering = true;
      _renderStep = 'Submitting render…';
      _videoReady = false;
      _renderError = null;
      _quiz = null;
    });

    try {
      final data = await ApiClient.post(
        '/api/courses/${widget.courseId}/lessons/${widget.lessonId}/render'
        '?lang=$_lang&style=$_style&course_type=detailed&economy=$_economy',
      ) as Map<String, dynamic>;

      final ridRaw = data['render_id'];
      final rid = ridRaw is int
          ? ridRaw
          : int.tryParse(ridRaw?.toString() ?? '') ?? 0;
      setState(() => _renderStep = 'Rendering…');

      while (true) {
        await Future.delayed(const Duration(seconds: 3));
        final st =
            await ApiClient.get('/api/renders/$rid/status') as Map<String, dynamic>;
        final status = st['status'] as String? ?? '';
        if (mounted) {
          setState(() => _renderStep = st['step'] as String? ?? 'Processing…');
        }
        if (['done', 'completed', 'success', 'ready'].contains(status)) {
          if (mounted) setState(() => _videoReady = true);
          if (_style == 'whiteboard_doodle' || _style == 'whiteboard') {
            _loadQuiz();
          }
          break;
        }
        if (['error', 'failed', 'failure'].contains(status)) {
          throw Exception(st['error'] ?? 'Render failed');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _renderError = e.toString());
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _loadQuiz() async {
    try {
      final data = await ApiClient.get(
              '/api/courses/${widget.courseId}/lessons/${widget.lessonId}/quiz?lang=$_lang')
          as Map<String, dynamic>;
      final qs = data['questions'] as List? ?? [];
      if (mounted && qs.isNotEmpty) setState(() => _quiz = qs);
    } catch (_) {}
  }

  String get _videoUrl =>
      ApiClient.downloadUrl(
          '/api/courses/${widget.courseId}/lessons/${widget.lessonId}/video?lang=$_lang');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AColors.cardBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Selectors row
        Row(children: [
          Expanded(child: _selector('Language', _lang, _kLangs,
              (v) => setState(() => _lang = v))),
          const SizedBox(width: 10),
          Expanded(child: _selector('Style', _style, _kStyles, (v) {
            setState(() {
              _style = v;
              _costData = null;
            });
          })),
          if (_isHeygen) ...[
            const SizedBox(width: 10),
            Expanded(child: _selector('Economy', _economy, _kEconomies,
                (v) => setState(() {
                      _economy = v;
                      _costData = null;
                    }))),
          ],
        ]),
        // HeyGen cost preview
        if (_isHeygen) ...[
          const SizedBox(height: 10),
          Row(children: [
            TextButton.icon(
              onPressed: _loadingCost ? null : _loadCost,
              icon: _loadingCost
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AColors.blue))
                  : const Icon(Icons.attach_money, size: 13, color: AColors.blue),
              label: const Text('Check Cost',
                  style: TextStyle(fontSize: 12, color: AColors.blue)),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            if (_costData != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AColors.amberSoft,
                    borderRadius: BorderRadius.circular(5)),
                child: Text(
                  '${_costData!['credits_used'] ?? '?'} credits',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AColors.orange),
                ),
              ),
              if (_costData!['usd_cost'] != null) ...[
                const SizedBox(width: 6),
                Text(
                    '\$${(_costData!['usd_cost'] as num).toStringAsFixed(3)}',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textMuted)),
              ],
            ],
          ]),
        ],
        const SizedBox(height: 10),
        // Render button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_rendering || _videoReady) ? null : _render,
            icon: Icon(
                _videoReady
                    ? Icons.check_circle_rounded
                    : Icons.play_arrow_rounded,
                size: 16),
            label: Text(
              _videoReady
                  ? 'Video Ready'
                  : _rendering
                      ? 'Rendering…'
                      : 'Render Video',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _videoReady ? AColors.green : AColors.ink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
            ),
          ),
        ),
        if (_rendering) ...[
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AColors.blue)),
            const SizedBox(width: 8),
            Text(_renderStep,
                style:
                    const TextStyle(fontSize: 11, color: AColors.textMuted)),
          ]),
        ],
        if (_renderError != null) ...[
          const SizedBox(height: 8),
          Text(_renderError!,
              style: const TextStyle(fontSize: 11, color: AColors.red)),
        ],
        if (_videoReady) ...[
          const SizedBox(height: 10),
          _WatchButton(url: _videoUrl),
        ],
        if (_quiz != null && _quiz!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _QuizSection(questions: _quiz!),
        ],
      ]),
    );
  }

  Widget _selector(String label, String value, Map<String, String> items,
      void Function(String) onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AColors.textSecond)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
            color: AColors.surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AColors.cardBorder)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 12, color: AColors.ink),
            items: items.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    ]);
  }
}

// ── Watch Button ───────────────────────────────────────────────────────────────

class _WatchButton extends StatelessWidget {
  const _WatchButton({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: AColors.ink, borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Icon(Icons.play_circle_filled_rounded,
              color: Colors.white, size: 18),
          SizedBox(width: 10),
          Text('Watch Video',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          Spacer(),
          Icon(Icons.open_in_new, color: Colors.white38, size: 14),
        ]),
      ),
    );
  }
}

// ── Quiz Section ───────────────────────────────────────────────────────────────

class _QuizSection extends StatefulWidget {
  const _QuizSection({required this.questions});
  final List<dynamic> questions;

  @override
  State<_QuizSection> createState() => _QuizSectionState();
}

class _QuizSectionState extends State<_QuizSection> {
  int _current = 0;
  int? _selected;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_current] as Map<String, dynamic>;
    final opts =
        List<String>.from(q['options'] as List? ?? ['True', 'False']);
    final correct = (q['correct_index'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AColors.amberSoft,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AColors.amber.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.quiz_rounded, size: 14, color: AColors.orange),
          const SizedBox(width: 6),
          Text(
              'Knowledge Check (${_current + 1}/${widget.questions.length})',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AColors.orange)),
        ]),
        const SizedBox(height: 8),
        Text(q['question'] as String? ?? '',
            style: const TextStyle(
                fontSize: 13, color: AColors.ink, height: 1.4)),
        const SizedBox(height: 10),
        for (int i = 0; i < opts.length; i++)
          GestureDetector(
            onTap:
                _revealed ? null : () => setState(() {
                  _selected = i;
                  _revealed = true;
                }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: _revealed && i == correct
                      ? AColors.greenSoft
                      : _revealed && i == _selected
                          ? AColors.redSoft
                          : AColors.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: _revealed && i == correct
                          ? AColors.green
                          : _revealed && i == _selected
                              ? AColors.red
                              : AColors.cardBorder)),
              child: Row(children: [
                if (_revealed && i == correct)
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: AColors.green)
                else if (_revealed && i == _selected)
                  const Icon(Icons.cancel_rounded,
                      size: 14, color: AColors.red)
                else
                  Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AColors.textMuted2))),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(opts[i],
                        style: TextStyle(
                            fontSize: 12,
                            color: _revealed &&
                                    (i == correct || i == _selected)
                                ? AColors.ink
                                : AColors.textSecond))),
              ]),
            ),
          ),
        if (_revealed && q['explanation'] != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AColors.cardBorder)),
            child: Text(q['explanation'] as String,
                style: const TextStyle(
                    fontSize: 12,
                    color: AColors.textSecond,
                    height: 1.4)),
          ),
        ],
        if (_revealed && _current < widget.questions.length - 1) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _current++;
                _selected = null;
                _revealed = false;
              }),
              child: const Text('Next Question →',
                  style: TextStyle(fontSize: 12, color: AColors.blue)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Library Tab ────────────────────────────────────────────────────────────────

class _LibraryTab extends StatefulWidget {
  const _LibraryTab();

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  List<LibraryItem> _items = [];
  bool _loading = true;
  String? _error;
  LibraryItem? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.get('/api/v1/courses/library');
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map) {
        list = (data['courses'] ?? data['items'] ?? data['data'] ?? [])
            as List;
      } else {
        list = [];
      }
      setState(() {
        _items = list
            .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
          child: Text(_error!,
              style: const TextStyle(color: AColors.red)));
    }
    if (_items.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: AColors.bg2,
              borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.library_books_rounded,
              size: 28, color: AColors.textMuted),
        ),
        const SizedBox(height: 12),
        const Text('No courses yet',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AColors.ink)),
        const SizedBox(height: 4),
        const Text('Generate a course to see it here',
            style: TextStyle(fontSize: 12, color: AColors.textMuted)),
      ]));
    }

    return Row(children: [
      // Sidebar list
      SizedBox(
        width: 300,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            color: AColors.surface,
            child: Row(children: [
              const Expanded(
                  child: Text('All Courses',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AColors.ink))),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    size: 16, color: AColors.textMuted),
                onPressed: _load,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          const Divider(height: 1, color: AColors.cardBorder),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final item = _items[i];
                final active = _selected?.scriptId == item.scriptId;
                return GestureDetector(
                  onTap: () => setState(() => _selected = item),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: active
                            ? AColors.blueSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: active
                                ? AColors.blue
                                : Colors.transparent)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.courseTitle,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? AColors.blue
                                      : AColors.ink),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(children: [
                            Expanded(
                                child: Text(item.targetAudience,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AColors.textMuted),
                                    overflow: TextOverflow.ellipsis)),
                            Text('${item.totalLessons} lessons',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AColors.textMuted)),
                          ]),
                        ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
      const VerticalDivider(width: 1, color: AColors.cardBorder),
      // Detail pane
      Expanded(
        child: _selected == null
            ? const Center(
                child: Text('Select a course to preview',
                    style: TextStyle(color: AColors.textMuted)))
            : _CourseDetailPane(item: _selected!),
      ),
    ]);
  }
}

class _CourseDetailPane extends StatelessWidget {
  const _CourseDetailPane({required this.item});
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text(item.courseTitle,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AColors.ink)),
          const SizedBox(height: 4),
          Text(item.targetAudience,
              style: const TextStyle(
                  fontSize: 13, color: AColors.textMuted)),
        ])),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () =>
              context.go('/admin/courses/${item.scriptId}'),
          icon: const Icon(Icons.open_in_new_rounded, size: 14),
          label: const Text('Open Editor',
              style: TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AColors.ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        _StatChip(label: 'Lessons', value: '${item.totalLessons}'),
        const SizedBox(width: 10),
        _StatChip(
            label: 'Duration',
            value: '${item.estimatedDurationMin} min'),
        const SizedBox(width: 10),
        _StatChip(label: 'Category', value: item.category),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AColors.cardBorder)),
        child: Row(children: [
          const Icon(Icons.insert_drive_file_rounded,
              size: 16, color: AColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
              child: Text(item.sourceFile,
                  style: const TextStyle(
                      fontSize: 12, color: AColors.textSecond))),
        ]),
      ),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          color: AColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AColors.cardBorder)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AColors.ink)),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AColors.textMuted)),
      ]),
    );
  }
}

// ── Documents Tab ──────────────────────────────────────────────────────────────

class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab();

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  List<DocumentInfo> _docs = [];
  bool _loading = true;
  bool _uploading = false;
  String? _uploadMsg;
  bool _uploadOk = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await DocumentService.listDocuments();
      setState(() => _docs = docs);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx', 'txt', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() {
      _uploading = true;
      _uploadMsg = 'Uploading ${file.name}…';
      _uploadOk = true;
    });
    try {
      await DocumentService.uploadDocument(file.bytes!, file.name);
      setState(() => _uploadMsg = '${file.name} uploaded successfully');
      await _load();
    } catch (e) {
      setState(() {
        _uploadMsg = 'Upload failed: $e';
        _uploadOk = false;
      });
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _delete(String sourceFile) async {
    try {
      await DocumentService.deleteDocument(sourceFile);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Knowledge Base Documents',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AColors.ink)),
              SizedBox(height: 2),
              Text(
                  'Documents used by the AI tutor and course generator',
                  style:
                      TextStyle(fontSize: 12, color: AColors.textMuted)),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file_rounded, size: 16),
            label:
                Text(_uploading ? 'Uploading…' : 'Upload Document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AColors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        if (_uploadMsg != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: _uploadOk
                    ? AColors.greenSoft
                    : AColors.redSoft,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: (_uploadOk ? AColors.green : AColors.red)
                        .withValues(alpha: 0.4))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  _uploadOk
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  size: 14,
                  color: _uploadOk ? AColors.green : AColors.red),
              const SizedBox(width: 6),
              Text(_uploadMsg!,
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          _uploadOk ? AColors.green : AColors.red)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(color: AColors.cardBorder),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text(_error!,
              style: const TextStyle(color: AColors.red))
        else if (_docs.isEmpty)
          Expanded(
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: AColors.bg2,
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.folder_open_rounded,
                  size: 32, color: AColors.textMuted),
            ),
            const SizedBox(height: 12),
            const Text('No documents yet',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AColors.ink)),
            const SizedBox(height: 4),
            const Text('Upload PDF, DOCX or PPTX files',
                style:
                    TextStyle(fontSize: 12, color: AColors.textMuted)),
          ])))
        else
          Expanded(
            child: ListView.separated(
              itemCount: _docs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AColors.cardBorder),
              itemBuilder: (_, i) {
                final doc = _docs[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: AColors.blueSoft,
                          borderRadius: BorderRadius.circular(8)),
                      child: Center(
                          child: Text(doc.ext,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AColors.blue))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          Text(doc.displayName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AColors.ink)),
                          const SizedBox(height: 2),
                          Text(
                              '${doc.chunkCount} chunks · ${doc.assetType}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AColors.textMuted)),
                        ])),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AColors.textMuted),
                      onPressed: () => _delete(doc.sourceFile),
                      tooltip: 'Remove from knowledge base',
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}

// ── Shared ─────────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip(
      {required this.label,
      required this.active,
      required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
            color: active ? AColors.blue : AColors.bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? AColors.blue : AColors.cardBorder)),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AColors.textMuted)),
      ),
    );
  }
}
