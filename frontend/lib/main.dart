import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const LmsApp());

const _base = '';

// ── API helpers ────────────────────────────────────────────────
Future<Map<String, dynamic>> _post(String path, Map body) async {
  final r = await http.post(Uri.parse('$_base$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body));
  return jsonDecode(r.body) as Map<String, dynamic>;
}
Future<Map<String, dynamic>> _get(String path) async {
  final r = await http.get(Uri.parse('$_base$path'));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

// ── App ────────────────────────────────────────────────────────
class LmsApp extends StatelessWidget {
  const LmsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LMS Author Studio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2563EB), useMaterial3: true),
        home: const _Home(),
      );
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _ctrl = TextEditingController();
  String _mode = 'detailed';
  String _lang = 'en';
  bool _busy = false;
  int _progress = 0;
  String _statusMsg = '';
  Map<String, dynamic>? _course;
  // true = paste JSON tab, false = paste raw text tab
  bool _importMode = false;

  // ── Import pre-built JSON (instant, no LLM) ────────────────────
  Future<void> _importJson() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _course = null; _statusMsg = 'Importing…'; _progress = 0; });
    try {
      final payload = jsonDecode(text) as Map<String, dynamic>;
      final r = await http.post(Uri.parse('$_base/api/courses/import'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode >= 400) {
        setState(() => _statusMsg = 'Import error: ${data['detail'] ?? data}');
        return;
      }
      final courseId = data['course_id'] as int;
      final c = await _get('/api/courses/$courseId');
      setState(() { _course = c; _statusMsg = data['message'] as String? ?? 'Imported!'; });
    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _course = null; _statusMsg = 'Starting…'; _progress = 0; });
    try {
      final job = await _post('/api/courses/generate',
          {'content_text': text, 'mode': _mode, 'languages': [_lang]});
      final jobId = job['id'] as int;
      while (true) {
        await Future.delayed(const Duration(seconds: 2));
        final j = await _get('/api/jobs/$jobId');
        setState(() {
          _progress = (j['progress'] as num).toInt();
          _statusMsg = '${j['progress']}%  ${j['step']}';
        });
        if (j['status'] == 'completed') {
          final c = await _get('/api/courses/${j['course_id']}');
          setState(() => _course = c);
          break;
        }
        if (j['status'] == 'failed') {
          setState(() => _statusMsg = 'Error: ${j['error']}');
          break;
        }
      }
    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: const Text('✨  LMS Author Studio'),
        elevation: 2,
      ),
      body: Row(children: [
        _LeftPanel(
          ctrl: _ctrl, mode: _mode, lang: _lang,
          importMode: _importMode,
          busy: _busy, progress: _progress, statusMsg: _statusMsg,
          onMode: (v) => setState(() => _mode = v),
          onLang: (v) => setState(() => _lang = v),
          onImportMode: (v) => setState(() { _importMode = v; _ctrl.clear(); }),
          onGenerate: _importMode ? _importJson : _generate,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _course == null ? const _Empty() : _CourseView(course: _course!, lang: _lang)),
      ]),
    );
  }
}

// ── Left panel ─────────────────────────────────────────────────
const _langs = {'en':'🇺🇸 English','hi':'🇮🇳 Hindi','es':'🇪🇸 Spanish',
  'fr':'🇫🇷 French','de':'🇩🇪 German','ar':'🇸🇦 Arabic','zh':'🇨🇳 Chinese',
  'ja':'🇯🇵 Japanese','pt':'🇧🇷 Portuguese','ru':'🇷🇺 Russian'};

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({required this.ctrl, required this.mode, required this.lang,
    required this.importMode,
    required this.busy, required this.progress, required this.statusMsg,
    required this.onMode, required this.onLang, required this.onImportMode,
    required this.onGenerate});
  final TextEditingController ctrl;
  final String mode, lang, statusMsg;
  final bool busy, importMode;
  final int progress;
  final ValueChanged<String> onMode, onLang;
  final ValueChanged<bool> onImportMode;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Mode toggle ──────────────────────────────────────────
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false,
              label: Text('📝 Raw Script'), icon: Icon(Icons.edit_note, size: 15)),
            ButtonSegment(value: true,
              label: Text('⚡ Import JSON'), icon: Icon(Icons.upload_rounded, size: 15)),
          ],
          selected: {importMode},
          onSelectionChanged: busy ? null : (s) => onImportMode(s.first),
        ),
        const SizedBox(height: 8),
        // hint banner for import mode
        if (importMode)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2563EB), width: 1)),
            child: const Text(
              '⚡ Paste the course_script JSON from your ingestion pipeline — imported instantly, no AI generation needed.',
              style: TextStyle(fontSize: 11, color: Color(0xFF1E3A8A))),
          ),
        Expanded(
          child: TextField(
            controller: ctrl, maxLines: null, expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: importMode
                  ? 'Paste course JSON here…'
                  : 'Paste your raw training script / manual here…',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(12)),
          ),
        ),
        const SizedBox(height: 12),
        // show generate options only for raw-script mode
        if (!importMode) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'quick',    label: Text('Quick'),    icon: Icon(Icons.bolt,   size: 16)),
              ButtonSegment(value: 'detailed', label: Text('Detailed'), icon: Icon(Icons.layers, size: 16)),
            ],
            selected: {mode},
            onSelectionChanged: busy ? null : (s) => onMode(s.first),
          ),
          const SizedBox(height: 10),
          DropdownButton<String>(
            value: lang, isExpanded: true, isDense: true,
            items: _langs.entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: busy ? null : (v) { if (v != null) onLang(v); },
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: importMode ? const Color(0xFF16A34A) : const Color(0xFF2563EB)),
          onPressed: busy ? null : onGenerate,
          icon: busy
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(importMode ? Icons.upload_rounded : Icons.auto_awesome),
          label: Text(busy
              ? (importMode ? 'Importing…' : 'Generating…')
              : (importMode ? 'Import Course (instant)' : 'Generate Course')),
        ),
        if (statusMsg.isNotEmpty || busy) ...[
          const SizedBox(height: 8),
          if (busy) LinearProgressIndicator(value: progress / 100),
          const SizedBox(height: 4),
          Text(statusMsg,
            style: TextStyle(fontSize: 12,
              color: statusMsg.startsWith('Error') ? Colors.red : Colors.black54)),
        ],
      ]),
    );
  }
}

// ── Empty ───────────────────────────────────────────────────────
class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.school_outlined, size: 72, color: Colors.black26),
      SizedBox(height: 16),
      Text('Generated course will appear here',
          style: TextStyle(color: Colors.black38, fontSize: 16)),
    ]));
}

// ── Course view ─────────────────────────────────────────────────
class _CourseView extends StatelessWidget {
  const _CourseView({required this.course, required this.lang});
  final Map<String, dynamic> course;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final modules = course['modules'] as List;
    return ListView(padding: const EdgeInsets.all(20), children: [
      // header card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)]),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(course['title'] ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(course['description'] ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4,
            children: [ for (final o in (course['learning_objectives'] as List? ?? []))
              Chip(label: Text(o as String, style: const TextStyle(fontSize: 11, color: Colors.white)),
                   backgroundColor: Colors.white24,
                   padding: EdgeInsets.zero, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ]),
        ]),
      ),
      const SizedBox(height: 20),
      for (final m in modules) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(m['title'] as String,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)))),
        for (final l in (m['lessons'] as List))
          _LessonCard(lesson: l, courseId: course['id'] as int, defaultLang: lang),
        const SizedBox(height: 4),
      ],
    ]);
  }
}

// ── Lesson card ─────────────────────────────────────────────────
class _LessonCard extends StatefulWidget {
  const _LessonCard({required this.lesson, required this.courseId, required this.defaultLang});
  final Map<String, dynamic> lesson;
  final int courseId;
  final String defaultLang;
  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  bool _expanded = false;
  bool _rendering = false;
  String _renderMsg = '';
  String _videoLang = 'en';
  String _videoStyle = 'claude_native';
  String _courseType = 'detailed';
  String _economy = 'lean';
  int? _renderId;
  Map<String, dynamic>? _cost;   // live cost preview from backend
  bool _loadingCost = false;

  @override
  void initState() {
    super.initState();
    _videoLang = widget.defaultLang;
  }

  bool get _isHeyGen =>
      _videoStyle == 'animated_scene' ||
      _videoStyle == 'whiteboard_doodle' ||
      _videoStyle == 'hybrid';

  // FREE cost preview — spends nothing, just estimates credits + reads balance.
  Future<void> _fetchCost() async {
    if (!_isHeyGen) { setState(() => _cost = null); return; }
    final id = widget.lesson['id'] as int;
    setState(() { _loadingCost = true; });
    try {
      final c = await _get(
          '/api/courses/${widget.courseId}/lessons/$id/cost?economy=$_economy');
      setState(() => _cost = c);
    } catch (_) {
      setState(() => _cost = null);
    } finally {
      setState(() => _loadingCost = false);
    }
  }

  void _viewSlides() {
    final id = widget.lesson['id'] as int;
    _launch(Uri.parse('$_base/api/courses/${widget.courseId}/lessons/$id/slides'));
  }

  void _launch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _renderVideo() async {
    final id = widget.lesson['id'] as int;
    setState(() { _rendering = true; _renderMsg = 'Starting render…'; });
    try {
      final res = await http.post(Uri.parse(
          '$_base/api/courses/${widget.courseId}/lessons/$id/render'
          '?lang=$_videoLang&style=$_videoStyle&course_type=$_courseType'
          '&economy=$_economy'));
      Map<String, dynamic> data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        setState(() => _renderMsg = 'Error: invalid server response (${res.statusCode})');
        return;
      }
      if (res.statusCode >= 400) {
        final detail = data['detail'] ?? data['error'] ?? data.toString();
        setState(() => _renderMsg = 'Error: $detail');
        return;
      }
      final rid = data['render_id'];
      if (rid == null) {
        setState(() => _renderMsg = 'Error: server did not return render_id');
        return;
      }
      setState(() { _renderId = rid as int; });

      // Poll until done — HeyGen videos can take 15-40 min
      while (true) {
        await Future.delayed(const Duration(seconds: 5));
        Map<String, dynamic> s;
        try {
          s = await _get('/api/renders/$rid/status');
        } catch (_) {
          continue; // transient network error — keep polling
        }
        final status = (s['status'] as String? ?? 'pending');
        if (status == 'running') {
          setState(() => _renderMsg = '⏳ Rendering… (HeyGen videos take 10-30 min)');
        } else if (status == 'pending') {
          setState(() => _renderMsg = '🕐 Queued…');
        } else {
          setState(() => _renderMsg = status);
        }
        if (status == 'completed') break;
        if (status == 'failed') {
          final err = s['error'] as String? ?? 'unknown error';
          setState(() => _renderMsg = 'Failed: $err');
          break;
        }
      }
    } catch (e) {
      setState(() => _renderMsg = 'Error: $e');
    } finally {
      setState(() => _rendering = false);
    }
  }

  void _watchVideo() {
    final id = widget.lesson['id'] as int;
    _launch(Uri.parse('$_base/api/courses/${widget.courseId}/lessons/$id/video?lang=$_videoLang'));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF2563EB),
            child: Icon(Icons.play_lesson, color: Colors.white, size: 18)),
          title: Text(l['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(l['summary'] as String? ?? '',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Tooltip(
              message: 'Open Interactive Slides',
              child: IconButton(
                icon: const Icon(Icons.slideshow, color: Color(0xFF2563EB), size: 22),
                onPressed: _viewSlides,
              ),
            ),
            IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                setState(() => _expanded = !_expanded);
                if (_expanded) _fetchCost();
              },
            ),
          ]),
        ),
        if (_expanded) ...[
          _Detail(lesson: l),
          _VideoPanel(
            rendering: _rendering,
            renderMsg: _renderMsg,
            renderId: _renderId,
            videoLang: _videoLang,
            videoStyle: _videoStyle,
            courseType: _courseType,
            economy: _economy,
            cost: _cost,
            loadingCost: _loadingCost,
            isHeyGen: _isHeyGen,
            onLangChanged: (v) => setState(() => _videoLang = v),
            onStyleChanged: (v) { setState(() => _videoStyle = v); _fetchCost(); },
            onCourseTypeChanged: (v) => setState(() => _courseType = v),
            onEconomyChanged: (v) { setState(() => _economy = v); _fetchCost(); },
            onRender: _renderVideo,
            onWatch: _watchVideo,
          ),
        ],
      ]),
    );
  }
}

// ── Lesson detail ───────────────────────────────────────────────
class _Detail extends StatelessWidget {
  const _Detail({required this.lesson});
  final Map<String, dynamic> lesson;

  Widget _rows(String title, List items) {
    if (items.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
        const SizedBox(height: 4),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(fontSize: 13)),
              Expanded(child: Text(
                item is Map ? '${item['situation']} → ${item['correct_action']}' : item.toString(),
                style: const TextStyle(fontSize: 13))),
            ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(),
        if ((lesson['simplified_explanation'] as String? ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Text(lesson['simplified_explanation'] as String,
                style: const TextStyle(fontSize: 13))),
        _rows('Key Takeaways',       lesson['key_takeaways']      as List? ?? []),
        _rows('Real-World Examples', lesson['real_world_examples'] as List? ?? []),
        _rows('Safety Scenarios',    lesson['safety_scenarios']   as List? ?? []),
      ]),
    );
  }
}

// ── Video panel ─────────────────────────────────────────────────
const _styles = {
  'animated_scene': '🎬 Animated Scene (HeyGen)',
  'whiteboard_doodle': '✍️ Whiteboard Doodle (HeyGen)',
  'claude_native': '🤖 Claude Animated (free)',
  'hybrid': '⚡ Hybrid (Claude + HeyGen)',
};

const _courseTypes = {
  'detailed': '📚 Detailed (per lesson)',
  'quick': '⚡ Quick (~15 min)',
};

// Credit-economy presets — controls how much narration is sent to HeyGen.
const _economyPresets = {
  'ultra_lean': '🪙 Ultra Lean (~3 cr)',
  'lean': '💰 Lean (~6 cr)',
  'standard': '📊 Standard (~12 cr)',
  'full': '💸 Full (uncapped)',
};

// Paid styles need the HeyGen key; until then they fail gracefully with a message.
const _paidStyles = {'animated_scene', 'whiteboard_doodle', 'hybrid'};

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({required this.rendering, required this.renderMsg,
    required this.renderId, required this.videoLang, required this.videoStyle,
    required this.courseType, required this.economy,
    required this.cost, required this.loadingCost, required this.isHeyGen,
    required this.onLangChanged, required this.onStyleChanged,
    required this.onCourseTypeChanged, required this.onEconomyChanged,
    required this.onRender, required this.onWatch});
  final bool rendering, loadingCost, isHeyGen;
  final String renderMsg, videoLang, videoStyle, courseType, economy;
  final int? renderId;
  final Map<String, dynamic>? cost;
  final ValueChanged<String> onLangChanged, onStyleChanged, onCourseTypeChanged,
      onEconomyChanged;
  final VoidCallback onRender, onWatch;

  // Build the live "this will cost X of Y credits" banner.
  Widget _costBanner() {
    if (!isHeyGen) return const SizedBox();
    if (loadingCost) {
      return const Padding(padding: EdgeInsets.only(top: 8),
        child: Text('Checking credit cost…',
          style: TextStyle(fontSize: 11, color: Colors.black45)));
    }
    final c = cost;
    if (c == null) return const SizedBox();
    final est = (c['estimated_cost'] as num?)?.toDouble() ?? 0;
    final bal = c['credits_remaining'] as int?;
    final affordable = c['affordable'] as bool? ?? true;
    final willCondense = c['will_condense'] as bool? ?? false;
    final secs = c['estimated_seconds'] as int? ?? 0;
    final color = affordable ? const Color(0xFF166534) : const Color(0xFFB91C1C);
    final bg = affordable ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(affordable ? Icons.savings : Icons.error_outline, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(child: Text(
            bal == null
              ? 'Estimated cost: ~${est.toStringAsFixed(0)} credits (~${secs}s video)'
              : 'This render: ~${est.toStringAsFixed(0)} of $bal credits  •  ~${secs}s video',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
        ]),
        if (willCondense)
          const Padding(padding: EdgeInsets.only(top: 3),
            child: Text('✓ Script auto-condensed to fit budget (quality kept, length trimmed).',
              style: TextStyle(fontSize: 10.5, color: Colors.black54))),
        if (!affordable)
          const Padding(padding: EdgeInsets.only(top: 3),
            child: Text('⚠ Not enough credits — top up or pick a leaner preset / free style.',
              style: TextStyle(fontSize: 10.5, color: Color(0xFFB91C1C)))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.movie_creation, size: 16, color: Color(0xFF7C3AED)),
          SizedBox(width: 6),
          Text('Generate Teaching Video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Language:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: videoLang, isDense: true,
              items: _langs.entries.map((e) =>
                DropdownMenuItem(value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: rendering ? null : (v) { if (v != null) onLangChanged(v); },
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Style:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: videoStyle, isDense: true,
              items: _styles.entries.map((e) =>
                DropdownMenuItem(value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: rendering ? null : (v) { if (v != null) onStyleChanged(v); },
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Course:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: courseType, isDense: true,
              items: _courseTypes.entries.map((e) =>
                DropdownMenuItem(value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: rendering ? null : (v) { if (v != null) onCourseTypeChanged(v); },
            ),
          ]),
          // Credit-economy preset — only relevant for HeyGen (paid) styles.
          if (isHeyGen)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Budget:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: economy, isDense: true,
                items: _economyPresets.entries.map((e) =>
                  DropdownMenuItem(value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: rendering ? null : (v) { if (v != null) onEconomyChanged(v); },
              ),
            ]),
        ]),
        // Live credit-cost preview (free; spends nothing).
        _costBanner(),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
            onPressed: rendering ? null : onRender,
            icon: rendering
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(rendering ? 'Rendering…' : 'Render Video'),
          ),
          if (renderMsg == 'completed') ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onWatch,
              icon: const Icon(Icons.smart_display, size: 16),
              label: const Text('Watch'),
            ),
          ],
        ]),
        if (renderMsg.isNotEmpty && renderMsg != 'completed')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(renderMsg,
                style: TextStyle(fontSize: 12,
                    color: renderMsg.startsWith('Failed') ? Colors.red : Colors.black54))),
      ]),
    );
  }
}
