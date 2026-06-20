import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/course_service.dart';
import '../../../core/services/video_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../data/models/course.dart';
import 'script_review_dialog.dart';

const _sarvamVoices = [
  ('ritu',    'Ritu',    'Female'),
  ('rahul',   'Rahul',   'Male'),
  ('kavitha', 'Kavitha', 'Female'),
  ('gokul',   'Gokul',   'Male'),
  ('priya',   'Priya',   'Female'),
  ('kavya',   'Kavya',   'Female'),
  ('ishita',  'Ishita',  'Female'),
  ('pooja',   'Pooja',   'Female'),
  ('simran',  'Simran',  'Female'),
  ('neha',    'Neha',    'Female'),
];

// (styleId, label, icon, isHeyGen)
const _styleOptions = [
  ('modern',            'AI Presenter',     Icons.auto_awesome_rounded,  false),
  ('flatcolor',         'Flat Color',       Icons.layers_rounded,        false),
  ('whiteboard',        'Whiteboard',       Icons.draw_rounded,          false),
  ('hybrid',            'Hybrid',           Icons.blur_on_rounded,       true),
  ('animated_scene',    'Animated Scene',   Icons.animation_rounded,     true),
  ('whiteboard_doodle', 'WB Doodle',        Icons.draw_outlined,         true),
];

const _heyGenStyles = {'hybrid', 'animated_scene', 'whiteboard_doodle'};

bool _isHeyGenStyle(String style) => _heyGenStyles.contains(style);

class VideoManagementScreen extends StatefulWidget {
  const VideoManagementScreen({super.key});

  @override
  State<VideoManagementScreen> createState() => _VideoManagementScreenState();
}

class _VideoManagementScreenState extends State<VideoManagementScreen> {
  List<Course>? _courses;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  // Per-course expansion and settings
  final Map<String, bool> _expanded = {};
  final Map<String, String> _courseStyle = {};
  final Map<String, String> _courseVoice = {};

  // Per-course lesson data (loaded lazily on expand)
  final Map<String, Map<String, dynamic>?> _courseDetail = {};
  // Per-course render jobs
  final Map<String, List<VideoRenderJob>> _renders = {};
  // Tracks which courses are actively loading detail
  final Set<String> _loadingDetail = {};

  @override
  void initState() {
    super.initState();
    _loadCourses();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollActiveRenders(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() { _loading = true; _error = null; });
    try {
      final courses = await CourseService.listLibrary();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _loading = false;
        for (final c in courses) {
          _courseStyle.putIfAbsent(c.id, () => 'modern');
          _courseVoice.putIfAbsent(c.id, () => 'ritu');
        }
        // If a HeyGen style was previously selected and voice is a Sarvam name,
        // reset to 'male' so the HeyGen voice chips display correctly.
        for (final c in courses) {
          final s = _courseStyle[c.id] ?? 'modern';
          if (_isHeyGenStyle(s)) {
            final v = _courseVoice[c.id] ?? '';
            if (v != 'male' && v != 'female') {
              _courseVoice[c.id] = 'male';
            }
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadCourseDetail(String scriptId) async {
    if (_loadingDetail.contains(scriptId)) return;
    setState(() => _loadingDetail.add(scriptId));
    try {
      final detail = await CourseService.getCourseDetail(scriptId);
      final renders = await VideoService.listRenders(scriptId);
      if (!mounted) return;
      setState(() {
        _courseDetail[scriptId] = detail;
        _renders[scriptId] = renders;
        _loadingDetail.remove(scriptId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDetail.remove(scriptId));
    }
  }

  Future<void> _pollActiveRenders() async {
    final expanded = _expanded.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    for (final id in expanded) {
      final jobs = _renders[id] ?? [];
      final hasActive = jobs.any(
        (j) => j.status == 'pending' || j.status == 'processing',
      );
      if (hasActive) {
        try {
          final fresh = await VideoService.listRenders(id);
          if (mounted) setState(() => _renders[id] = fresh);
        } catch (_) {}
      }
    }
  }

  Future<void> _renderAll(String scriptId) async {
    final style = _courseStyle[scriptId] ?? 'modern';
    final voice = _courseVoice[scriptId] ?? 'ritu';
    try {
      final count = await VideoService.generateAll(
        scriptId,
        style: style,
        voice: voice,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Started $count render job(s) · voice: $voice'),
        backgroundColor: ArrestoColors.ink,
      ));
      await _loadCourseDetail(scriptId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: ArrestoColors.red,
      ));
    }
  }

  Future<void> _renderLesson(
    String scriptId, {
    int? moduleNumber,
    int? lessonNumber,
    int? itemIndex,
    String lang = 'en',
  }) async {
    final style = _courseStyle[scriptId] ?? 'modern';
    final voice = _courseVoice[scriptId] ?? 'ritu';
    try {
      await VideoService.renderLesson(
        scriptId,
        moduleNumber: moduleNumber,
        lessonNumber: lessonNumber,
        itemIndex: itemIndex,
        lang: lang,
        style: style,
        voice: voice,
      );
      if (!mounted) return;
      await _loadCourseDetail(scriptId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Render failed: $e'),
        backgroundColor: ArrestoColors.red,
      ));
    }
  }

  Future<void> _openReviewDialog(
    String scriptId, {
    required String lessonTitle,
    required String lessonRef,
    int? moduleNumber,
    int? lessonNumber,
    int? itemIndex,
    String lang = 'en',
  }) async {
    final detail = _courseDetail[scriptId];
    if (detail == null) return;
    final courseScript =
        detail['course_script'] as Map<String, dynamic>? ?? {};
    final style = _courseStyle[scriptId] ?? 'modern';
    final voice = _courseVoice[scriptId] ?? 'ritu';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScriptReviewDialog(
        scriptId: scriptId,
        lessonTitle: lessonTitle,
        lessonRef: lessonRef,
        fullCourseScript: courseScript,
        moduleNumber: moduleNumber,
        lessonNumber: lessonNumber,
        itemIndex: itemIndex,
        lang: lang,
        style: style,
        voice: voice,
        onRenderStarted: () => _loadCourseDetail(scriptId),
      ),
    );
    if (mounted) await _loadCourseDetail(scriptId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArrestoColors.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: ArrestoColors.orange))
                : _error != null
                    ? _buildError()
                    : _buildCourseList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: ArrestoColors.surface,
        border:
            Border(bottom: BorderSide(color: ArrestoColors.cardBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ArrestoColors.ink,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.videocam_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Video Studio', style: ArrestoText.h3()),
                Text('Render and manage lesson videos course-by-course',
                    style: ArrestoText.small()),
              ],
            ),
          ),
          ArrestoButton(
            label: 'Refresh',
            variant: ArrestoButtonVariant.ghost,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            onPressed: _loadCourses,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: ArrestoColors.textMuted2, size: 48),
          const SizedBox(height: 12),
          Text('Could not load courses', style: ArrestoText.body()),
          const SizedBox(height: 16),
          ArrestoButton(
            label: 'Retry',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCourses,
          ),
        ],
      ),
    );
  }

  Widget _buildCourseList() {
    final courses = _courses ?? [];
    if (courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined,
                color: ArrestoColors.textMuted2, size: 48),
            const SizedBox(height: 12),
            Text('No courses in the library yet',
                style: ArrestoText.body()),
            const SizedBox(height: 6),
            Text('Generate a course first using Course Generator',
                style: ArrestoText.small()),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: courses.length,
      itemBuilder: (ctx, i) => _CourseCard(
        course: courses[i],
        expanded: _expanded[courses[i].id] ?? false,
        style: _courseStyle[courses[i].id] ?? 'modern',
        voice: _courseVoice[courses[i].id] ?? 'ritu',
        detail: _courseDetail[courses[i].id],
        renders: _renders[courses[i].id] ?? [],
        loadingDetail: _loadingDetail.contains(courses[i].id),
        onToggle: () {
          final id = courses[i].id;
          final wasExpanded = _expanded[id] ?? false;
          setState(() => _expanded[id] = !wasExpanded);
          if (!wasExpanded && !_courseDetail.containsKey(id)) {
            _loadCourseDetail(id);
          }
        },
        onStyleChanged: (s) =>
            setState(() => _courseStyle[courses[i].id] = s),
        onVoiceChanged: (v) =>
            setState(() => _courseVoice[courses[i].id] = v),
        onRenderAll: () => _renderAll(courses[i].id),
        onRenderLesson: ({
          int? moduleNumber,
          int? lessonNumber,
          int? itemIndex,
          String lang = 'en',
        }) =>
            _renderLesson(
              courses[i].id,
              moduleNumber: moduleNumber,
              lessonNumber: lessonNumber,
              itemIndex: itemIndex,
              lang: lang,
            ),
        onReviewLesson: ({
          required String lessonTitle,
          required String lessonRef,
          int? moduleNumber,
          int? lessonNumber,
          int? itemIndex,
          String lang = 'en',
        }) =>
            _openReviewDialog(
              courses[i].id,
              lessonTitle: lessonTitle,
              lessonRef: lessonRef,
              moduleNumber: moduleNumber,
              lessonNumber: lessonNumber,
              itemIndex: itemIndex,
              lang: lang,
            ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  final Course course;
  final bool expanded;
  final String style;
  final String voice;
  final Map<String, dynamic>? detail;
  final List<VideoRenderJob> renders;
  final bool loadingDetail;
  final VoidCallback onToggle;
  final ValueChanged<String> onStyleChanged;
  final ValueChanged<String> onVoiceChanged;
  final VoidCallback onRenderAll;
  final Function({int? moduleNumber, int? lessonNumber, int? itemIndex, String lang}) onRenderLesson;
  final Function({
    required String lessonTitle,
    required String lessonRef,
    int? moduleNumber,
    int? lessonNumber,
    int? itemIndex,
    String lang,
  }) onReviewLesson;

  const _CourseCard({
    required this.course,
    required this.expanded,
    required this.style,
    required this.voice,
    required this.detail,
    required this.renders,
    required this.loadingDetail,
    required this.onToggle,
    required this.onStyleChanged,
    required this.onVoiceChanged,
    required this.onRenderAll,
    required this.onRenderLesson,
    required this.onReviewLesson,
  });

  VideoRenderJob? _jobForLesson(String lessonRef) {
    final jobs = renders
        .where((j) => j.lessonRef == lessonRef)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return jobs.isEmpty ? null : jobs.first;
  }

  @override
  Widget build(BuildContext context) {
    final completedCount =
        renders.where((j) => j.status == 'completed').length;
    final activeCount = renders
        .where((j) => j.status == 'pending' || j.status == 'processing')
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: ArrestoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? ArrestoColors.orange.withValues(alpha: 0.4)
              : ArrestoColors.cardBorder,
          width: expanded ? 1.5 : 1,
        ),
        boxShadow: ArrestoColors.sh1,
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: ArrestoColors.orangeTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.play_circle_filled_rounded,
                        color: ArrestoColors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(course.title,
                            style: ArrestoText.bodyBold(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.menu_book_rounded,
                              size: 11,
                              color: ArrestoColors.textMuted2),
                          const SizedBox(width: 3),
                          Text('${course.lessons} lessons',
                              style: ArrestoText.xs()),
                          if (completedCount > 0) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle_rounded,
                                size: 11, color: ArrestoColors.green),
                            const SizedBox(width: 3),
                            Text('$completedCount rendered',
                                style: ArrestoText.xs(
                                    color: ArrestoColors.green)),
                          ],
                          if (activeCount > 0) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: ArrestoColors.orange,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text('$activeCount rendering…',
                                style: ArrestoText.xs(
                                    color: ArrestoColors.orange)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: ArrestoColors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (expanded)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: ArrestoColors.cardBorder)),
              ),
              child: loadingDetail
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: ArrestoColors.orange),
                      ),
                    )
                  : _buildExpandedContent(),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Style + Voice + Render All row
          _buildControlsBar(),
          const SizedBox(height: 16),

          // Lesson list
          Text('Lessons', style: ArrestoText.label()),
          const SizedBox(height: 8),
          _buildLessonList(),
        ],
      ),
    );
  }

  Widget _buildControlsBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ArrestoColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArrestoColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Style selector
          Text('Video Style', style: ArrestoText.xs()),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _styleOptions.map((s) {
              final selected = style == s.$1;
              final isHeyGen = s.$4;
              return GestureDetector(
                onTap: () {
                  onStyleChanged(s.$1);
                  // Auto-adjust voice when switching engine type
                  if (isHeyGen && voice != 'male' && voice != 'female') {
                    onVoiceChanged('male');
                  } else if (!isHeyGen && (voice == 'male' || voice == 'female')) {
                    onVoiceChanged('ritu');
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? (isHeyGen ? ArrestoColors.orange : ArrestoColors.ink)
                        : ArrestoColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? (isHeyGen ? ArrestoColors.orange : ArrestoColors.ink)
                          : isHeyGen
                              ? ArrestoColors.orange.withValues(alpha: 0.35)
                              : ArrestoColors.lineStrong,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.$3,
                          size: 13,
                          color: selected
                              ? Colors.white
                              : isHeyGen
                                  ? ArrestoColors.orange
                                  : ArrestoColors.textMuted),
                      const SizedBox(width: 5),
                      Text(s.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : isHeyGen
                                    ? ArrestoColors.orange
                                    : ArrestoColors.textSecondary,
                          )),
                      if (isHeyGen && !selected) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: ArrestoColors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('HG',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: ArrestoColors.orange,
                              )),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Voice selector — Male/Female for HeyGen, Sarvam speakers otherwise
          if (_isHeyGenStyle(style)) ...[
            Text('Presenter Voice (HeyGen)', style: ArrestoText.xs()),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final mv in [('male', 'Male', Icons.person_2_rounded),
                                  ('female', 'Female', Icons.person_rounded)])
                  GestureDetector(
                    onTap: () => onVoiceChanged(mv.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: voice == mv.$1
                            ? ArrestoColors.orange
                            : ArrestoColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: voice == mv.$1
                              ? ArrestoColors.orange
                              : ArrestoColors.lineStrong,
                          width: voice == mv.$1 ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(mv.$3,
                              size: 13,
                              color: voice == mv.$1
                                  ? Colors.white
                                  : ArrestoColors.textMuted),
                          const SizedBox(width: 5),
                          Text(mv.$2,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: voice == mv.$1
                                    ? Colors.white
                                    : ArrestoColors.textSecondary,
                              )),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                Text('Transcript: Sarvam female',
                    style: ArrestoText.xs(color: ArrestoColors.textMuted2)),
              ],
            ),
          ] else ...[
            Text('Voice (Sarvam Bulbul-v3)', style: ArrestoText.xs()),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _sarvamVoices.map((v) {
                  final selected = voice == v.$1;
                  final isFemale = v.$3 == 'Female';
                  return GestureDetector(
                    onTap: () => onVoiceChanged(v.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? (isFemale
                                ? ArrestoColors.blueSoft
                                : ArrestoColors.orangeTint)
                            : ArrestoColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? (isFemale
                                  ? ArrestoColors.blue
                                  : ArrestoColors.orange)
                              : ArrestoColors.lineStrong,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFemale
                                ? Icons.person_rounded
                                : Icons.person_2_rounded,
                            size: 12,
                            color: selected
                                ? (isFemale
                                    ? ArrestoColors.blue
                                    : ArrestoColors.orange)
                                : ArrestoColors.textMuted2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            v.$2,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? (isFemale
                                      ? ArrestoColors.blue
                                      : ArrestoColors.orange)
                                  : ArrestoColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Render All button
          ArrestoButton(
            label: 'Render All Lessons',
            fullWidth: true,
            variant: ArrestoButtonVariant.dark,
            icon: const Icon(Icons.video_call_rounded),
            onPressed: onRenderAll,
          ),
        ],
      ),
    );
  }

  Widget _buildLessonList() {
    final script = detail?['course_script'] as Map<String, dynamic>?;
    if (script == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No script data available.',
            style: ArrestoText.small()),
      );
    }

    final modules = script['modules'] as List? ?? [];
    if (modules.isNotEmpty) {
      return Column(
        children: [
          for (final mod in modules)
            _buildModuleSection(mod as Map<String, dynamic>),
        ],
      );
    }

    // Custom course (items-based)
    final items = script['items'] as List? ?? [];
    final slideItems = items
        .asMap()
        .entries
        .where((e) =>
            (e.value as Map<String, dynamic>)['type'] == 'slide' ||
            (e.value as Map<String, dynamic>)['type'] == 'closing_slide')
        .toList();

    return Column(
      children: slideItems.map((e) {
        final title = (e.value as Map<String, dynamic>)['title'] as String? ??
            'Slide ${e.key + 1}';
        final lessonRef = 'item_${e.key}';
        return _buildLessonRow(
          title: title,
          lessonRef: lessonRef,
          onReview: () => onReviewLesson(
            lessonTitle: title,
            lessonRef: lessonRef,
            itemIndex: e.key,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModuleSection(Map<String, dynamic> mod) {
    final mNum = mod['module_number'] as int? ?? 1;
    final mTitle = mod['module_title'] as String? ?? 'Module $mNum';
    final lessons =
        (mod['lessons'] as List? ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(mTitle,
              style: ArrestoText.small(color: ArrestoColors.textMuted)
                  .copyWith(fontWeight: FontWeight.w700)),
        ),
        ...lessons.map((les) {
          final lNum = les['lesson_number'] as int? ?? 1;
          final lTitle =
              les['lesson_title'] as String? ?? 'Lesson $lNum';
          final lessonRef = 'module_${mNum}_lesson_$lNum';
          return _buildLessonRow(
            title: lTitle,
            lessonRef: lessonRef,
            onReview: () => onReviewLesson(
              lessonTitle: lTitle,
              lessonRef: lessonRef,
              moduleNumber: mNum,
              lessonNumber: lNum,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLessonRow({
    required String title,
    required String lessonRef,
    required VoidCallback onReview,
  }) {
    final job = _jobForLesson(lessonRef);
    final status = job?.status;
    final isActive = status == 'processing' || status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ArrestoColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ArrestoColors.line),
      ),
      child: Row(
        children: [
          _StatusDot(status: status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: ArrestoText.bodySm(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (job != null)
                  Text(_statusLabel(job),
                      style: ArrestoText.xs(
                          color: _statusColor(job.status))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isActive)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ArrestoColors.orange,
              ),
            )
          else
            GestureDetector(
              onTap: onReview,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ArrestoColors.orangeTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: ArrestoColors.orange.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.preview_rounded,
                      size: 13,
                      color: ArrestoColors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Review',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ArrestoColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(VideoRenderJob job) {
    return switch (job.status) {
      'completed' => 'Ready · ${job.ttsEngine.isNotEmpty ? job.ttsEngine : 'TTS'}${job.voice.isNotEmpty ? " · ${job.voice}" : ""}',
      'processing' => 'Rendering…',
      'pending' => 'Queued',
      'failed' => 'Failed: ${job.error ?? "unknown error"}',
      _ => job.status,
    };
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => ArrestoColors.green,
        'processing' => ArrestoColors.orange,
        'pending' => ArrestoColors.textMuted,
        'failed' => ArrestoColors.red,
        _ => ArrestoColors.textMuted,
      };
}

// ── Status dot ────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final String? status;
  const _StatusDot({this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => ArrestoColors.green,
      'processing' => ArrestoColors.orange,
      'pending' => ArrestoColors.amber,
      'failed' => ArrestoColors.red,
      _ => ArrestoColors.line,
    };

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
