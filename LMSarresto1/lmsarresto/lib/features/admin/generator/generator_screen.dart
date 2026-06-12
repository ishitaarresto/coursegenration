import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/api/models.dart';
import '../../../core/api/course_service.dart';
import '../../../core/api/document_service.dart';
import '../../../core/api/video_service.dart';
import '../../../core/providers/library_provider.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_badge.dart';

// ── Wizard design tokens ──────────────────────────────────────────────────────
const _kRust  = Color(0xFFC0461E);
const _kGreen = Color(0xFF1F8A4C);
const _kCta   = Color(0xFFF2B233);
const _kBeige = Color(0xFFF5F1EA);

const _kStepLabels = [
  'Requirements', 'Source', 'Settings',
  'Generate', 'Review Script', 'Visual Style',
  'Videos', 'Review', 'Publish',
];

// Video style options: (id, label, icon, provider)
const List<(String, String, IconData, String)> _kVideoStyles = [
  ('animated_scene',    'Animated Scene',    Icons.movie_creation_outlined, 'HeyGen'),
  ('whiteboard_doodle', 'Whiteboard Doodle', Icons.gesture_rounded,         'HeyGen'),
  ('hybrid',            'Hybrid',            Icons.dynamic_feed_rounded,    'HeyGen'),
  ('modern',            'Modern',            Icons.slideshow_rounded,       'Free'),
  ('flatcolor',         'Flat Color',        Icons.format_paint_rounded,    'Free'),
  ('whiteboard',        'Whiteboard',        Icons.edit_note_rounded,       'Free'),
];

// ═════════════════════════════════════════════════════════════════════════════
// Generator Screen — 9-step wizard
// ═════════════════════════════════════════════════════════════════════════════

class GeneratorScreen extends ConsumerStatefulWidget {
  const GeneratorScreen({super.key});
  @override
  ConsumerState<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends ConsumerState<GeneratorScreen> {
  // ── Wizard navigation ─────────────────────────────────────────────────────
  int _wizardStep = 0;

  // ── Step 1: Requirements ──────────────────────────────────────────────────
  final _titleCtrl   = TextEditingController();
  final _topicCtrl   = TextEditingController();
  final _descCtrl    = TextEditingController();
  String _audience   = 'Field Workers';
  String _difficulty = 'Intermediate';
  final List<String> _objectives = [];
  final _objCtrl = TextEditingController();

  // ── Step 2: Source Document ───────────────────────────────────────────────
  bool _useUpload = false;
  String? _uploadFilename;
  List<int>? _uploadBytes;
  String? _selectedDoc;

  // ── Step 3: Course Settings ───────────────────────────────────────────────
  final _instructionsCtrl = TextEditingController();
  String _courseFormat = 'standard';
  String _language     = 'en';

  // ── Generation state ──────────────────────────────────────────────────────
  bool _uploading   = false;
  bool _generating  = false;
  int  _genProgress = 0;
  String _genStep   = '';
  CourseScript? _script;
  String? _scriptId;
  String? _genError;

  // ── Step 6: Visual Style ──────────────────────────────────────────────────
  String _videoStyle    = 'modern';
  String _videoLanguage = 'en';

  // ── Steps 7–8: Video Generation ──────────────────────────────────────────
  bool _renderingVideos = false;
  bool _videosRendered  = false;
  final Map<String, String> _renderStatus = {};
  final Map<String, String> _renderIdMap  = {};

  @override
  void dispose() {
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    _descCtrl.dispose();
    _objCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  // ── Validation ────────────────────────────────────────────────────────────
  bool get _step1Valid => _titleCtrl.text.trim().isNotEmpty;

  bool get _step2Valid {
    if (_useUpload) return _uploadFilename != null && _uploadBytes != null;
    return _selectedDoc != null;
  }

  bool get _canContinue {
    if (_generating || _renderingVideos) return false;
    switch (_wizardStep) {
      case 0: return _step1Valid;
      case 1: return _step2Valid;
      case 3: return _step2Valid;
      case 6: return _script != null;
      default: return true;
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _goNext() {
    if (_wizardStep < 8) setState(() => _wizardStep++);
  }

  void _goBack() {
    if (_wizardStep > 0 && !_generating && !_renderingVideos) {
      setState(() => _wizardStep--);
    }
  }

  void _onCtaTap() {
    if (_wizardStep == 3) {
      _generate();
    } else if (_wizardStep == 6) {
      if (!_videosRendered) {
        _renderAllVideos();
      } else {
        _goNext();
      }
    } else if (_wizardStep == 8) {
      context.go('/admin/courses');
    } else {
      _goNext();
    }
  }

  // ── File picker ───────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() { _uploadFilename = file.name; _uploadBytes = file.bytes!; });
  }

  // ── Generation ────────────────────────────────────────────────────────────
  Future<void> _generate() async {
    setState(() {
      _generating = true; _uploading = false;
      _genError = null; _genProgress = 0; _genStep = 'Preparing…';
      _script = null; _scriptId = null;
    });

    try {
      String docName;
      if (_useUpload) {
        setState(() { _uploading = true; _genStep = 'Uploading document…'; });
        await DocumentService.uploadDocument(_uploadBytes!, _uploadFilename!);
        ref.read(documentsProvider.notifier).refresh();
        docName = _uploadFilename!;
        setState(() { _uploading = false; _genStep = 'Starting generation…'; });
      } else {
        docName = _selectedDoc!;
        setState(() => _genStep = 'Starting generation…');
      }

      final jobId = await CourseService.generateCourse(
        sourceFile:     docName,
        courseTitle:    _titleCtrl.text.trim().isEmpty
            ? null : _titleCtrl.text.trim(),
        targetAudience: _audience,
        instructions:   _instructionsCtrl.text.trim().isEmpty
            ? null : _instructionsCtrl.text.trim(),
        courseFormat:   _courseFormat,
      );

      await _pollJob(jobId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _uploading  = false;
          _genError   = e.toString();
        });
      }
    }
  }

  Future<void> _pollJob(String jobId) async {
    int errors = 0;
    while (true) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final job = await CourseService.getJobStatus(jobId);
        errors = 0;
        if (mounted) {
          setState(() { _genProgress = job.progress; _genStep = job.step; });
        }

        if (job.isCompleted) {
          if (job.courseScript != null) {
            final script = CourseScript.fromJson(
                {'script_id': jobId, 'course_script': job.courseScript});
            await ref.read(libraryProvider.notifier).refresh();
            if (mounted) setState(() {
              _generating = false;
              _script     = script;
              _scriptId   = jobId;
              _wizardStep = 4;
            });
          } else {
            if (mounted) setState(() {
              _generating = false;
              _genError   = 'Generation completed but no script was returned.';
            });
          }
          break;
        }

        if (job.isFailed) {
          if (mounted) setState(() {
            _generating = false;
            _genError   = job.error ?? 'Generation failed.';
          });
          break;
        }
      } catch (e) {
        errors++;
        if (errors >= 5) {
          if (mounted) setState(() {
            _generating = false;
            _genError   = 'Lost connection after $errors retries.\n\n$e';
          });
          break;
        }
        if (mounted) setState(() => _genStep = 'Retrying… ($errors/5 errors)');
      }
    }
  }

  // ── Video rendering ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> _getRenderableItems() {
    if (_script == null) return [];
    if (_script!.isCustom) {
      return _script!.items.asMap().entries
          .where((e) =>
              e.value.type == 'slide' || e.value.type == 'closing_slide')
          .map((e) => {
                'key':      'i${e.key}',
                'index':    e.key,
                'title':    e.value.title,
                'subtitle': e.value.type,
              })
          .toList();
    } else {
      final result = <Map<String, dynamic>>[];
      for (final mod in _script!.modules) {
        for (final les in mod.lessons) {
          result.add({
            'key':          'm${mod.moduleNumber}_l${les.lessonNumber}',
            'moduleNumber': mod.moduleNumber,
            'lessonNumber': les.lessonNumber,
            'title':        les.title,
            'subtitle':     'Module ${mod.moduleNumber}',
          });
        }
      }
      return result;
    }
  }

  Future<void> _renderAllVideos() async {
    final items = _getRenderableItems();
    if (items.isEmpty) {
      setState(() { _videosRendered = true; });
      _goNext();
      return;
    }
    setState(() {
      _renderingVideos = true;
      _renderStatus.clear();
      _renderIdMap.clear();
      for (final item in items) {
        _renderStatus[item['key'] as String] = 'queued';
      }
    });

    try {
      await Future.wait(items.map(_renderOne));
    } finally {
      if (mounted) setState(() {
        _renderingVideos = false;
        _videosRendered  = true;
        _wizardStep      = 7;
      });
    }
  }

  Future<void> _renderOne(Map<String, dynamic> item) async {
    final key = item['key'] as String;
    if (!mounted) return;
    setState(() => _renderStatus[key] = 'rendering');
    try {
      final String renderId;
      if (_script!.isCustom) {
        renderId = await VideoService.renderItem(
          scriptId: _scriptId!,
          itemIndex: item['index'] as int,
          lang: _videoLanguage,
          style: _videoStyle,
        );
      } else {
        renderId = await VideoService.renderLesson(
          scriptId:     _scriptId!,
          moduleNumber: item['moduleNumber'] as int,
          lessonNumber: item['lessonNumber'] as int,
          lang: _videoLanguage,
          style: _videoStyle,
        );
      }
      if (mounted) _renderIdMap[key] = renderId;
      // Poll until done (5s intervals, max 5 min)
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        try {
          final r = await VideoService.getRenderStatus(renderId);
          if (mounted) setState(() {
            _renderStatus[key] = r.isCompleted ? 'completed'
                : r.isFailed ? 'failed' : r.status;
          });
          if (r.isDone) return;
        } catch (_) {}
      }
      if (mounted) setState(() => _renderStatus[key] = 'failed');
    } catch (e) {
      if (mounted) setState(() => _renderStatus[key] = 'failed');
    }
  }

  void _reset() => setState(() {
    _wizardStep = 0;
    _script = null; _genError = null; _scriptId = null;
    _selectedDoc = null; _uploadFilename = null; _uploadBytes = null;
    _titleCtrl.clear(); _topicCtrl.clear(); _descCtrl.clear();
    _instructionsCtrl.clear(); _objectives.clear();
    _genProgress = 0; _genStep = '';
    _audience = 'Field Workers'; _difficulty = 'Intermediate';
    _courseFormat = 'standard'; _language = 'en';
    _videoStyle = 'modern'; _videoLanguage = 'en';
    _renderingVideos = false; _videosRendered = false;
    _renderStatus.clear(); _renderIdMap.clear();
  });

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBeige,
      child: Column(children: [
        _buildWizardHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AColors.cardBorder),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12, offset: const Offset(0, 3))],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: _buildCurrentStep(),
              ),
            ),
          ),
        ),
        _buildWizardFooter(),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildWizardHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      color: _kBeige,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Course Generator', style: AText.h2()),
          const Spacer(),
          Text('Step ${_wizardStep + 1} of 9',
              style: AText.small(color: AColors.textMuted)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (_wizardStep + 1) / 9,
            backgroundColor: const Color(0xFFDDD5C5),
            valueColor: const AlwaysStoppedAnimation(_kRust),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 20),
        _buildStepper(),
      ]),
    );
  }

  Widget _buildStepper() {
    return Row(children: [
      for (int i = 0; i < _kStepLabels.length; i++) ...[
        _StepDot(
          index: i,
          label: _kStepLabels[i],
          state: i < _wizardStep
              ? _StepState.completed
              : i == _wizardStep
                  ? _StepState.current
                  : _StepState.upcoming,
        ),
        if (i < _kStepLabels.length - 1)
          Expanded(child: Container(
            height: 1,
            color: i < _wizardStep ? _kGreen : AColors.line)),
      ],
    ]);
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildWizardFooter() {
    final isGenerateStep = _wizardStep == 3;
    final isRenderStep   = _wizardStep == 6 && !_videosRendered;
    final isPublishStep  = _wizardStep == 8;
    final isBusy = _generating || _renderingVideos;

    final String ctaLabel;
    if (isGenerateStep) {
      ctaLabel = _generating ? 'Generating…' : 'Generate Course';
    } else if (isRenderStep) {
      ctaLabel = _renderingVideos ? 'Rendering…' : 'Render Videos';
    } else if (isPublishStep) {
      ctaLabel = 'Go to Library';
    } else {
      ctaLabel = 'Continue';
    }

    final IconData ctaIcon;
    if (isGenerateStep) {
      ctaIcon = _generating ? Icons.hourglass_empty_rounded : Icons.auto_awesome_rounded;
    } else if (isRenderStep) {
      ctaIcon = _renderingVideos ? Icons.hourglass_empty_rounded : Icons.play_circle_rounded;
    } else if (isPublishStep) {
      ctaIcon = Icons.library_books_rounded;
    } else {
      ctaIcon = Icons.arrow_forward_rounded;
    }

    final ctaBg = isPublishStep ? AColors.ink : _kCta;
    final ctaFg = isPublishStep ? Colors.white : AColors.ink;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
      color: _kBeige,
      child: Row(children: [
        if (_wizardStep > 0)
          OutlinedButton.icon(
            onPressed: isBusy ? null : _goBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AColors.textSecond,
              side: const BorderSide(color: AColors.cardBorder),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
            ),
          ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _canContinue ? _onCtaTap : null,
          icon: isBusy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AColors.ink))
              : Icon(ctaIcon, size: 16),
          label: Text(ctaLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: ctaBg,
            foregroundColor: ctaFg,
            disabledBackgroundColor: AColors.bg2,
            disabledForegroundColor: AColors.textMuted,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            elevation: 0,
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP ROUTING
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCurrentStep() {
    switch (_wizardStep) {
      case 0: return _buildStep1Requirements();
      case 1: return _buildStep2Source();
      case 2: return _buildStep3Settings();
      case 3: return _buildStep4Generate();
      case 4: return _buildStep5ReviewScript();
      case 5: return _buildStep6VisualStyle();
      case 6: return _buildStep7GenerateVideos();
      case 7: return _buildStep8Review();
      case 8: return _buildStep9Publish();
      default: return const SizedBox.shrink();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 1 — Requirements
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep1Requirements() {
    const audiences = [
      'Field Workers', 'New Site Workers', 'Field Supervisors',
      'Safety Officers', 'All Staff', 'Management',
    ];
    const difficulties = ['Beginner', 'Intermediate', 'Advanced'];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Course Requirements', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Tell us about the course you want to create.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 28),

      _FieldLabel('Course Name *'),
      const SizedBox(height: 6),
      TextField(
        controller: _titleCtrl,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'e.g. Defensive Driving Essentials',
        ),
      ),
      const SizedBox(height: 20),

      _FieldLabel('Topic / Subject Area'),
      const SizedBox(height: 6),
      TextField(
        controller: _topicCtrl,
        decoration: const InputDecoration(
          hintText: 'e.g. Road safety, PPE usage, Fire prevention',
        ),
      ),
      const SizedBox(height: 20),

      _FieldLabel('Course Description'),
      const SizedBox(height: 6),
      TextField(
        controller: _descCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Brief overview of what learners will cover…',
        ),
      ),
      const SizedBox(height: 20),

      _FieldLabel('Target Audience'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: AColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
          color: AColors.surface,
        ),
        child: DropdownButton<String>(
          value: _audience,
          isExpanded: true,
          underline: const SizedBox(),
          items: audiences.map((a) =>
              DropdownMenuItem(value: a, child: Text(a))).toList(),
          onChanged: (v) { if (v != null) setState(() => _audience = v); },
        ),
      ),
      const SizedBox(height: 20),

      _FieldLabel('Difficulty Level'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: difficulties.map((d) {
          final sel = _difficulty == d;
          return GestureDetector(
            onTap: () => setState(() => _difficulty = d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? AColors.ink : AColors.bg2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: sel ? AColors.ink : AColors.cardBorder),
              ),
              child: Text(d, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : AColors.textSecond,
              )),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 24),

      _FieldLabel('Learning Objectives'),
      const SizedBox(height: 4),
      Text('What should learners be able to do after this course?',
          style: AText.tiny(color: AColors.textMuted)),
      const SizedBox(height: 10),

      if (_objectives.isNotEmpty) ...[
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _objectives.asMap().entries.map((e) {
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _kGreen.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(e.value,
                    style: const TextStyle(
                        fontSize: 12, color: _kGreen)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(
                      () => _objectives.removeAt(e.key)),
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: _kGreen),
                ),
              ]),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
      ],

      Row(children: [
        Expanded(
          child: TextField(
            controller: _objCtrl,
            decoration: const InputDecoration(
              hintText: 'e.g. Identify fall hazards on a worksite',
            ),
            onSubmitted: (_) => _addObjective(),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _addObjective,
          style: OutlinedButton.styleFrom(
            foregroundColor: _kRust,
            side: const BorderSide(color: _kRust),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
          child: const Text('Add'),
        ),
      ]),

      if (!_step1Valid)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('A course name is required to continue.',
              style: AText.tiny(color: AColors.red)),
        ),
    ]);
  }

  void _addObjective() {
    final text = _objCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _objectives.add(text); _objCtrl.clear(); });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 2 — Source Document
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep2Source() {
    final docsAsync = ref.watch(documentsProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Source Document', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Select an existing document or upload a new file.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 24),

      Row(children: [
        _Chip(
          label: 'Use Existing', selected: !_useUpload,
          onTap: () => setState(() {
            _useUpload = false;
            _uploadFilename = null;
            _uploadBytes = null;
          }),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Upload New File', selected: _useUpload,
          onTap: () => setState(() {
            _useUpload = true; _selectedDoc = null;
          }),
        ),
      ]),
      const SizedBox(height: 16),

      if (_useUpload) ...[
        GestureDetector(
          onTap: _pickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 32, horizontal: 24),
            decoration: BoxDecoration(
              color: _uploadFilename != null
                  ? AColors.amberSoft : AColors.bg2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _uploadFilename != null
                    ? AColors.amber : AColors.cardBorder,
                width: _uploadFilename != null ? 2 : 1,
              ),
            ),
            child: Column(children: [
              Icon(
                _uploadFilename != null
                    ? Icons.description_rounded
                    : Icons.upload_file_rounded,
                size: 40,
                color: _uploadFilename != null
                    ? AColors.orange : AColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                _uploadFilename ?? 'Click to browse',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _uploadFilename != null
                      ? FontWeight.w600 : FontWeight.normal,
                  color: _uploadFilename != null
                      ? AColors.ink : AColors.textSecond,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _uploadFilename != null
                    ? 'Click to change file' : 'PDF, DOCX, or PPTX',
                style: const TextStyle(
                    fontSize: 12, color: AColors.textMuted),
              ),
            ]),
          ),
        ),
      ] else ...[
        docsAsync.when(
          loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator())),
          error: (e, _) => Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AColors.redSoft,
                borderRadius: BorderRadius.circular(10)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Could not load documents',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AColors.red)),
              const SizedBox(height: 4),
              Text('$e', style: const TextStyle(
                  fontSize: 12, color: AColors.red)),
              const SizedBox(height: 10),
              AButton(
                label: 'Retry', size: AButtonSize.sm,
                variant: AButtonVariant.ghost,
                onPressed: () =>
                    ref.read(documentsProvider.notifier).refresh(),
              ),
            ]),
          ),
          data: (docs) => docs.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text('No documents in the knowledge base yet.',
                      style: TextStyle(
                          color: AColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 12),
                  AButton(
                    label: 'Go to Settings',
                    size: AButtonSize.sm,
                    icon: Icons.settings_rounded,
                    onPressed: () => context.go('/admin/settings'),
                  ),
                ])
              : Column(
                  children: docs.map((doc) => GestureDetector(
                    onTap: () => setState(
                        () => _selectedDoc = doc.sourceFile),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedDoc == doc.sourceFile
                            ? AColors.amberSoft : AColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedDoc == doc.sourceFile
                              ? AColors.amber : AColors.cardBorder,
                          width: _selectedDoc == doc.sourceFile ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text(doc.ext, style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AColors.blue)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(doc.displayName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AColors.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text('${doc.chunkCount} knowledge chunks',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AColors.textMuted)),
                        ])),
                        if (_selectedDoc == doc.sourceFile)
                          const Icon(Icons.check_circle_rounded,
                              color: AColors.amber, size: 20),
                      ]),
                    ),
                  )).toList(),
                ),
        ),
      ],
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 3 — Settings
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep3Settings() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Course Settings', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Customize how the AI structures your course.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 24),

      _FieldLabel('Language'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: AColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
          color: AColors.surface,
        ),
        child: DropdownButton<String>(
          value: _language, isExpanded: true,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'en',    child: Text('English')),
            DropdownMenuItem(value: 'en-in', child: Text('English (India)')),
            DropdownMenuItem(value: 'hi',
                child: Text('Hindi  (Sarvam AI)')),
            DropdownMenuItem(value: 'ta',    child: Text('Tamil')),
            DropdownMenuItem(value: 'te',    child: Text('Telugu')),
            DropdownMenuItem(value: 'bn',    child: Text('Bengali')),
            DropdownMenuItem(value: 'gu',    child: Text('Gujarati')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _language = v);
          },
        ),
      ),
      const SizedBox(height: 20),

      _FieldLabel('Course Format'),
      const SizedBox(height: 8),
      Row(children: [
        _Chip(
          label: 'Standard', sublabel: 'AI designs structure',
          selected: _courseFormat == 'standard',
          onTap: () => setState(() => _courseFormat = 'standard'),
        ),
        const SizedBox(width: 10),
        _Chip(
          label: 'Blueprint', sublabel: 'You define structure',
          selected: _courseFormat == 'custom',
          onTap: () => setState(() => _courseFormat = 'custom'),
        ),
      ]),
      const SizedBox(height: 20),

      _FieldLabel(
        _courseFormat == 'custom'
            ? 'Blueprint Instructions (required)'
            : 'Instructions (optional)',
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _instructionsCtrl,
        maxLines: 7,
        decoration: InputDecoration(
          hintText: _courseFormat == 'custom'
              ? 'Describe the exact structure:\n• Slide count and topics'
                  '\n• Quiz placement\n• Language (e.g. Hindi)'
                  '\n• Specific requirements'
              : 'Optional guidance for the AI:\n• Tone or style'
                  '\n• Focus areas\n• Topics to skip',
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 4 — Generate
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep4Generate() {
    if (_genError != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Generate Course Script', style: AText.h3()),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AColors.redSoft,
              borderRadius: BorderRadius.circular(12)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.error_outline_rounded,
                  color: AColors.red, size: 18),
              const SizedBox(width: 8),
              Text('Generation failed',
                  style: AText.smallBold(color: AColors.red)),
            ]),
            const SizedBox(height: 8),
            Text(_genError!, style: const TextStyle(
                fontSize: 12, color: AColors.red, height: 1.4)),
            const SizedBox(height: 12),
            AButton(label: 'Try Again', size: AButtonSize.sm,
                onPressed: _generate),
          ]),
        ),
      ]);
    }

    if (_generating) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Generating Course Script', style: AText.h3()),
        const SizedBox(height: 4),
        Text('Claude is reading your document and writing the course.',
            style: AText.body(color: AColors.textMuted)),
        const SizedBox(height: 48),
        Center(child: Column(children: [
          SizedBox(
            width: 84, height: 84,
            child: CircularProgressIndicator(
              value: _genProgress > 0 ? _genProgress / 100 : null,
              strokeWidth: 6,
              valueColor: const AlwaysStoppedAnimation(_kRust),
              backgroundColor: const Color(0xFFDDD5C5),
            ),
          ),
          const SizedBox(height: 20),
          if (_genProgress > 0)
            Text('$_genProgress%', style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800,
                color: _kRust)),
          const SizedBox(height: 8),
          Text(_uploading ? 'Uploading document…' : _genStep,
              style: AText.body(color: AColors.textMuted)),
          const SizedBox(height: 6),
          Text('This usually takes 1–3 minutes.',
              style: AText.tiny(color: AColors.textMuted2)),
        ])),
      ]);
    }

    // Ready state — summary panel
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Generate Course Script', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Claude will read your document and write a full course.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kBeige,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDD5C5)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('READY TO GENERATE',
              style: AText.eyebrow(color: _kRust)),
          const SizedBox(height: 14),
          _SummaryRow(Icons.title_rounded, 'Course',
              _titleCtrl.text.trim()),
          _SummaryRow(Icons.people_outline_rounded, 'Audience', _audience),
          _SummaryRow(Icons.signal_cellular_alt_rounded,
              'Difficulty', _difficulty),
          _SummaryRow(Icons.language_rounded, 'Language',
              _langLabel(_language)),
          _SummaryRow(Icons.format_list_bulleted_rounded, 'Format',
              _courseFormat == 'standard' ? 'Standard' : 'Blueprint'),
          if (_selectedDoc != null)
            _SummaryRow(Icons.description_outlined, 'Source',
                _selectedDoc!.length > 36
                    ? '…${_selectedDoc!.substring(_selectedDoc!.length - 36)}'
                    : _selectedDoc!),
          if (_uploadFilename != null)
            _SummaryRow(Icons.upload_file_outlined, 'Upload',
                _uploadFilename!),
        ]),
      ),
      const SizedBox(height: 16),
      Text('Click "Generate Course" below to start.',
          style: AText.small(color: AColors.textMuted)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 5 — Review Script
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep5ReviewScript() {
    if (_script == null) {
      return Center(child: Column(children: [
        const SizedBox(height: 40),
        Icon(Icons.description_outlined, size: 64,
            color: AColors.textMuted2),
        const SizedBox(height: 16),
        Text('No script yet — complete Step 4 to generate.',
            style: AText.body(color: AColors.textMuted)),
      ]));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.check_circle_rounded,
              color: _kGreen, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Course Script Ready', style: AText.h3()),
          Text('Review the structure before continuing.',
              style: AText.small()),
        ])),
        AButton(
          label: 'View in Library',
          icon: Icons.library_books_rounded,
          size: AButtonSize.sm, variant: AButtonVariant.ghost,
          onPressed: () => context.go('/admin/courses'),
        ),
      ]),
      const SizedBox(height: 24),

      // Course header card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Row(children: [
            Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 13),
            SizedBox(width: 6),
            Text('Generated successfully',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(_script!.title, style: const TextStyle(
              color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w800)),
          if (_script!.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_script!.description, style: const TextStyle(
                color: Colors.white70, fontSize: 12, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(children: [
            _StatChip(
              icon: Icons.layers_rounded,
              label: _script!.isCustom
                  ? '${_script!.items.length} items'
                  : '${_script!.modules.length} modules',
            ),
            if (!_script!.isCustom) ...[
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.school_rounded,
                label:
                    '${_script!.modules.fold(0, (n, m) => n + m.lessons.length)} lessons',
              ),
            ],
          ]),
        ]),
      ),
      const SizedBox(height: 20),

      if (!_script!.isCustom)
        ...(_script!.modules.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AColors.cardBorder),
            ),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: AColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text('${e.key + 1}',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AColors.blue))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(e.value.title,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AColors.ink))),
              Text('${e.value.lessons.length} lessons',
                  style: AText.tiny()),
            ]),
          ),
        ))),

      if (_script!.isCustom)
        ...(_script!.items.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AColors.cardBorder),
            ),
            child: Row(children: [
              ABadge(e.value.type,
                  variant: e.value.type == 'quiz'
                      ? ABadgeVariant.orange : ABadgeVariant.blue),
              const SizedBox(width: 12),
              Expanded(child: Text(e.value.title,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AColors.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ))),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 6 — Visual Style
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep6VisualStyle() {
    const langs = {
      'en':    'English',
      'en-in': 'English (India)',
      'hi':    'Hindi (Sarvam AI)',
      'ta':    'Tamil',
      'te':    'Telugu',
      'bn':    'Bengali',
      'gu':    'Gujarati',
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Visual Style', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Choose how your teaching videos will look.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 28),

      _FieldLabel('Narration Language'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: AColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
          color: AColors.surface,
        ),
        child: DropdownButton<String>(
          value: _videoLanguage, isExpanded: true,
          underline: const SizedBox(),
          items: langs.entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) { if (v != null) setState(() => _videoLanguage = v); },
        ),
      ),
      const SizedBox(height: 24),

      _FieldLabel('Video Style'),
      const SizedBox(height: 4),
      Text('Select the visual template for your lesson videos.',
          style: AText.tiny(color: AColors.textMuted)),
      const SizedBox(height: 12),

      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: _kVideoStyles.map((s) {
          final (id, name, icon, provider) = s;
          final sel = _videoStyle == id;
          final isHeyGen = provider == 'HeyGen';
          final providerColor = isHeyGen
              ? const Color(0xFF7C3AED) : _kGreen;
          return GestureDetector(
            onTap: () => setState(() => _videoStyle = id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sel ? _kRust.withValues(alpha: 0.06) : AColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? _kRust : AColors.cardBorder,
                  width: sel ? 2 : 1,
                ),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Icon(icon, size: 22,
                      color: sel ? _kRust : AColors.textMuted),
                  const Spacer(),
                  if (sel)
                    Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(
                          color: _kRust, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                          size: 12, color: Colors.white),
                    ),
                ]),
                const Spacer(),
                Text(name, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: sel ? _kRust : AColors.ink)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: providerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(provider, style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: providerColor)),
                ),
              ]),
            ),
          );
        }).toList(),
      ),

      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: Color(0xFF7C3AED)),
          SizedBox(width: 8),
          Expanded(child: Text(
            'HeyGen styles require a HeyGen API key. Free styles work without one.',
            style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED)),
          )),
        ]),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 7 — Generate Videos
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep7GenerateVideos() {
    final items = _getRenderableItems();

    // Done state
    if (_videosRendered) {
      final done   = _renderStatus.values.where((s) => s == 'completed').length;
      final failed = _renderStatus.values.where((s) => s == 'failed').length;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Videos Generated', style: AText.h3()),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.check_circle_rounded, color: _kGreen, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rendering complete', style: AText.bodyBold()),
              const SizedBox(height: 2),
              Text(
                '$done of ${items.length} rendered'
                    '${failed > 0 ? ' · $failed failed' : ''}',
                style: AText.small(color: AColors.textMuted),
              ),
            ])),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Click "Continue" to review your videos.',
            style: AText.small(color: AColors.textMuted)),
      ]);
    }

    // Rendering in progress
    if (_renderingVideos) {
      final done = _renderStatus.values
          .where((s) => s == 'completed' || s == 'failed').length;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Generating Teaching Videos', style: AText.h3()),
        const SizedBox(height: 4),
        Text('Rendering AI videos for each lesson.',
            style: AText.body(color: AColors.textMuted)),
        const SizedBox(height: 20),
        // Overall progress
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: items.isEmpty ? 0 : done / items.length,
            backgroundColor: const Color(0xFFDDD5C5),
            valueColor: const AlwaysStoppedAnimation(_kRust),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Text('$done of ${items.length} lessons rendered',
            style: AText.small(color: AColors.textMuted)),
        const SizedBox(height: 20),
        ...items.map((item) {
          final key    = item['key'] as String;
          final status = _renderStatus[key] ?? 'queued';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RenderStatusRow(
              title:    item['title'] as String,
              subtitle: item['subtitle'] as String,
              status:   status,
            ),
          );
        }),
      ]);
    }

    // Ready state — summary before rendering
    final selectedStyleName = _kVideoStyles
        .where((s) => s.$1 == _videoStyle)
        .map((s) => s.$2)
        .firstOrNull ?? _videoStyle;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Generate Teaching Videos', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Render AI-powered videos for each lesson in your course.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kBeige,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDD5C5)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RENDER PLAN', style: AText.eyebrow(color: _kRust)),
          const SizedBox(height: 14),
          _SummaryRow(Icons.layers_rounded, 'Lessons',
              '${items.length} lessons to render'),
          _SummaryRow(Icons.movie_creation_outlined, 'Style',
              selectedStyleName),
          _SummaryRow(Icons.language_rounded, 'Language',
              _langLabel(_videoLanguage)),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Icon(Icons.schedule_rounded, size: 14, color: AColors.textMuted),
        const SizedBox(width: 6),
        Text('Each video takes 2–5 minutes. Renders run in parallel.',
            style: AText.tiny(color: AColors.textMuted)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.skip_next_rounded, size: 14, color: AColors.textMuted),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() { _videosRendered = true; _wizardStep = 7; }),
          child: Text('Skip this step and continue without videos',
              style: AText.tiny(color: AColors.blue)),
        ),
      ]),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 8 — Review
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep8Review() {
    final items = _getRenderableItems();

    if (!_videosRendered || items.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Review Videos', style: AText.h3()),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AColors.cardBorder),
          ),
          child: Column(children: [
            Icon(Icons.video_library_outlined,
                size: 40, color: AColors.textMuted2),
            const SizedBox(height: 12),
            Text('No videos were rendered.',
                style: AText.bodyBold(color: AColors.textMuted)),
            const SizedBox(height: 6),
            Text('Go back to Step 7 to generate videos, or continue to publish.',
                style: AText.small(color: AColors.textMuted),
                textAlign: TextAlign.center),
          ]),
        ),
      ]);
    }

    final completed = items.where((i) =>
        _renderStatus[i['key']] == 'completed').length;
    final failed = items.where((i) =>
        _renderStatus[i['key']] == 'failed').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Review Videos', style: AText.h3()),
      const SizedBox(height: 4),
      Text('Preview and download your lesson videos.',
          style: AText.body(color: AColors.textMuted)),
      const SizedBox(height: 20),

      // Stats
      Row(children: [
        _ReviewStat('$completed', 'Rendered', _kGreen),
        const SizedBox(width: 12),
        _ReviewStat('${items.length - completed - failed}', 'Pending',
            AColors.textMuted),
        const SizedBox(width: 12),
        if (failed > 0) _ReviewStat('$failed', 'Failed', AColors.red),
      ]),
      const SizedBox(height: 20),

      ...items.map((item) {
        final key      = item['key'] as String;
        final status   = _renderStatus[key] ?? 'pending';
        final renderId = _renderIdMap[key];
        final isDone   = status == 'completed';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDone
                  ? _kGreen.withValues(alpha: 0.04) : AColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDone
                    ? _kGreen.withValues(alpha: 0.25) : AColors.cardBorder,
              ),
            ),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item['title'] as String, style: AText.bodyBold(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(item['subtitle'] as String, style: AText.tiny()),
              ])),
              const SizedBox(width: 12),
              _StatusChip(status),
              if (isDone && renderId != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(VideoService.downloadUrl(renderId)),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('MP4'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kGreen,
                    side: BorderSide(color: _kGreen.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ]),
          ),
        );
      }),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 9 — Publish
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStep9Publish() {
    final totalLessons = _script == null ? 0
        : _script!.isCustom
            ? _script!.items.length
            : _script!.modules.fold(0, (n, m) => n + m.lessons.length);
    final totalModules = _script == null ? 0
        : _script!.isCustom ? 0 : _script!.modules.length;
    final videosRendered = _renderStatus.values
        .where((s) => s == 'completed').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.celebration_rounded, size: 36, color: _kGreen),
        ),
        const SizedBox(height: 16),
        Text('Your Course is Ready!', style: AText.h3()),
        const SizedBox(height: 6),
        Text('Review the summary and go to the library.',
            style: AText.body(color: AColors.textMuted)),
      ])),
      const SizedBox(height: 28),

      // Summary card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_script?.title ?? _titleCtrl.text.trim(),
              style: const TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _PublishChip(Icons.people_outline_rounded, _audience),
            _PublishChip(Icons.signal_cellular_alt_rounded, _difficulty),
            _PublishChip(Icons.language_rounded, _langLabel(_language)),
            if (totalModules > 0)
              _PublishChip(Icons.layers_rounded, '$totalModules modules'),
            _PublishChip(Icons.school_rounded, '$totalLessons lessons'),
            if (videosRendered > 0)
              _PublishChip(Icons.movie_creation_outlined,
                  '$videosRendered videos'),
          ]),
        ]),
      ),
      const SizedBox(height: 24),

      // Action tiles
      Row(children: [
        Expanded(child: _ActionTile(
          icon: Icons.library_books_rounded,
          color: AColors.blue,
          title: 'Course Library',
          subtitle: 'View & manage all courses',
          onTap: () => context.go('/admin/courses'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile(
          icon: Icons.people_rounded,
          color: _kGreen,
          title: 'Assign Learners',
          subtitle: 'Enroll learners in this course',
          onTap: () => context.go('/admin/learners'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile(
          icon: Icons.add_circle_outline_rounded,
          color: _kRust,
          title: 'New Course',
          subtitle: 'Generate another course',
          onTap: _reset,
        )),
      ]),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Step dot widget
// ═════════════════════════════════════════════════════════════════════════════

enum _StepState { completed, current, upcoming }

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.state,
  });
  final int index;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final isCompleted = state == _StepState.completed;
    final isCurrent   = state == _StepState.current;
    final bgColor = isCompleted ? _kGreen
        : isCurrent  ? _kRust
        : AColors.bg2;
    final fgColor = (isCompleted || isCurrent)
        ? Colors.white : AColors.textMuted;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: (!isCompleted && !isCurrent)
              ? Border.all(color: AColors.cardBorder, width: 1.5)
              : null,
        ),
        child: Center(
          child: isCompleted
              ? const Icon(Icons.check_rounded, size: 14,
                  color: Colors.white)
              : Text('${index + 1}', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: fgColor)),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        width: 60,
        child: Text(label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
            color: isCurrent ? _kRust
                : isCompleted ? _kGreen
                : AColors.textMuted,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Lang label helper
// ═════════════════════════════════════════════════════════════════════════════

String _langLabel(String code) {
  const m = {
    'en': 'English', 'en-in': 'English (India)',
    'hi': 'Hindi', 'ta': 'Tamil', 'te': 'Telugu',
    'bn': 'Bengali', 'gu': 'Gujarati',
  };
  return m[code] ?? code;
}

// ═════════════════════════════════════════════════════════════════════════════
// Rich preview — used by the Library detail view (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

class _GeneratedPreview extends StatelessWidget {
  const _GeneratedPreview({
    required this.script,
    required this.scriptId,
    required this.defaultLang,
    required this.onReset,
  });
  final CourseScript script;
  final String scriptId;
  final String defaultLang;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AButton(
            label: 'View in Library',
            icon: Icons.library_books_rounded,
            onPressed: () => context.go('/admin/courses'),
          ),
          const SizedBox(width: 10),
          AButton(
            label: 'Generate Another',
            icon: Icons.refresh_rounded,
            variant: AButtonVariant.ghost,
            onPressed: onReset,
          ),
        ]),
        const SizedBox(height: 20),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.white,
                  size: 15),
              SizedBox(width: 6),
              Text('Course generated successfully',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            Text(script.title, style: const TextStyle(
                color: Colors.white, fontSize: 22,
                fontWeight: FontWeight.w800)),
            if (script.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(script.description, style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4)),
            ],
            if (script.objectives.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: script.objectives.map((o) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(o, style: const TextStyle(
                      color: Colors.white, fontSize: 11)),
                )).toList(),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              _StatChip(
                icon: Icons.layers_rounded,
                label: script.isCustom
                    ? '${script.items.length} items'
                    : '${script.modules.length} modules',
              ),
              if (!script.isCustom) ...[
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.school_rounded,
                  label:
                      '${script.modules.fold(0, (n, m) => n + m.lessons.length)} lessons',
                ),
              ],
            ]),
          ]),
        ),
        const SizedBox(height: 24),

        if (!script.isCustom)
          ...script.modules.map((m) => _ModulePreview(
              module: m, scriptId: scriptId, defaultLang: defaultLang)),

        if (script.isCustom)
          ...script.items.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ItemPreview(
              item: e.value, index: e.key,
              scriptId: scriptId, defaultLang: defaultLang,
            ),
          )),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 11,
          fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Module section ─────────────────────────────────────────────────────────

class _ModulePreview extends StatelessWidget {
  const _ModulePreview({
    required this.module, required this.scriptId,
    required this.defaultLang,
  });
  final CourseModule module;
  final String scriptId;
  final String defaultLang;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text('${module.moduleNumber}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: Color(0xFF1D4ED8)))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(module.title, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: AColors.ink))),
        ]),
      ),
      ...module.lessons.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _LessonPreview(
          lesson: l, scriptId: scriptId,
          moduleNumber: module.moduleNumber, defaultLang: defaultLang,
        ),
      )),
      const SizedBox(height: 12),
    ]);
  }
}

// ── Lesson card ────────────────────────────────────────────────────────────

class _LessonPreview extends StatefulWidget {
  const _LessonPreview({
    required this.lesson, required this.scriptId,
    required this.moduleNumber, required this.defaultLang,
  });
  final CourseLesson lesson;
  final String scriptId;
  final int moduleNumber;
  final String defaultLang;
  @override
  State<_LessonPreview> createState() => _LessonPreviewState();
}

class _LessonPreviewState extends State<_LessonPreview> {
  bool _expanded  = false;
  late String _lang;
  String _style   = 'animated_scene';
  String? _renderId;
  VideoRender? _render;
  bool _rendering   = false;
  String _renderMsg = '';
  Timer? _pollTimer;

  @override
  void initState() { super.initState(); _lang = widget.defaultLang; }

  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  Future<void> _startRender() async {
    setState(() {
      _rendering = true; _renderMsg = 'Starting…';
      _renderId = null; _render = null;
    });
    try {
      final rid = await VideoService.renderLesson(
        scriptId:     widget.scriptId,
        moduleNumber: widget.moduleNumber,
        lessonNumber: widget.lesson.lessonNumber,
        lang: _lang, style: _style,
      );
      setState(() { _renderId = rid; _renderMsg = 'Processing…'; });
      _pollTimer = Timer.periodic(
          const Duration(seconds: 4), (_) => _poll());
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
        if (r.isDone) {
          _pollTimer?.cancel();
          setState(() => _rendering = false);
        }
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
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(
                    color: Color(0x1A2563EB), shape: BoxShape.circle),
                child: Center(child: Text('${l.lessonNumber}',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB)))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(l.title, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AColors.ink)),
                if (l.summary.isNotEmpty)
                  Text(l.summary, style: const TextStyle(
                      fontSize: 12, color: AColors.textMuted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const Icon(Icons.movie_creation_outlined,
                  size: 14, color: AColors.textMuted),
              const SizedBox(width: 6),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AColors.textMuted),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (l.keyTakeaways.isNotEmpty) ...[
                const Text('Key Takeaways', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AColors.ink)),
                const SizedBox(height: 6),
                ...l.keyTakeaways.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('•  ',
                        style: TextStyle(color: AColors.amber)),
                    Expanded(child: Text(t, style: const TextStyle(
                        fontSize: 13, color: AColors.textSecond))),
                  ]),
                )),
                const SizedBox(height: 14),
              ],
              if (l.narration.isNotEmpty) ...[
                const Text('Narration Preview', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AColors.ink)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AColors.cardBorder),
                  ),
                  child: Text(
                    l.narration.length > 300
                        ? '${l.narration.substring(0, 300)}…'
                        : l.narration,
                    style: const TextStyle(
                        fontSize: 12, color: AColors.textSecond,
                        height: 1.5)),
                ),
                const SizedBox(height: 14),
              ],
              _PreviewVideoPanel(
                lang: _lang, style: _style,
                rendering: _rendering, renderMsg: _renderMsg,
                render: _render, renderId: _renderId,
                onLangChange:  (v) => setState(() => _lang  = v),
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

// ── Blueprint item card ────────────────────────────────────────────────────

class _ItemPreview extends StatefulWidget {
  const _ItemPreview({
    required this.item, required this.index,
    required this.scriptId, required this.defaultLang,
  });
  final CourseItem item;
  final int index;
  final String scriptId;
  final String defaultLang;
  @override
  State<_ItemPreview> createState() => _ItemPreviewState();
}

class _ItemPreviewState extends State<_ItemPreview> {
  bool _expanded  = false;
  late String _lang;
  String _style   = 'animated_scene';
  String? _renderId;
  VideoRender? _render;
  bool _rendering   = false;
  String _renderMsg = '';
  Timer? _pollTimer;

  bool get _renderable =>
      widget.item.type == 'slide' || widget.item.type == 'closing_slide';

  @override
  void initState() { super.initState(); _lang = widget.defaultLang; }

  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  Future<void> _startRender() async {
    setState(() {
      _rendering = true; _renderMsg = 'Starting…';
      _renderId = null; _render = null;
    });
    try {
      final rid = await VideoService.renderItem(
        scriptId: widget.scriptId, itemIndex: widget.index,
        lang: _lang, style: _style,
      );
      setState(() { _renderId = rid; _renderMsg = 'Processing…'; });
      _pollTimer = Timer.periodic(
          const Duration(seconds: 4), (_) => _poll());
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
        if (r.isDone) {
          _pollTimer?.cancel();
          setState(() => _rendering = false);
        }
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
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(children: [
              ABadge(item.type,
                  variant: isQuiz
                      ? ABadgeVariant.orange : ABadgeVariant.blue),
              const SizedBox(width: 12),
              Expanded(child: Text(item.title, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: AColors.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (_renderable) ...[
                const Icon(Icons.movie_creation_outlined,
                    size: 14, color: AColors.textMuted),
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
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (item.bullets.isNotEmpty) ...[
                const Text('Slide Content', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AColors.ink)),
                const SizedBox(height: 6),
                ...item.bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('•  ',
                        style: TextStyle(color: AColors.amber)),
                    Expanded(child: Text(b, style: const TextStyle(
                        fontSize: 13, color: AColors.textSecond))),
                  ]),
                )),
                const SizedBox(height: 14),
              ],
              if (isQuiz)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AColors.amberSoft,
                    borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.quiz_outlined, size: 16,
                        color: AColors.orange),
                    SizedBox(width: 8),
                    Text('Quiz items cannot be rendered as video.',
                        style: TextStyle(fontSize: 12,
                            color: AColors.orange)),
                  ]),
                ),
              if (_renderable)
                _PreviewVideoPanel(
                  lang: _lang, style: _style,
                  rendering: _rendering, renderMsg: _renderMsg,
                  render: _render, renderId: _renderId,
                  onLangChange:  (v) => setState(() => _lang  = v),
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

// ── Shared video panel ─────────────────────────────────────────────────────

class _PreviewVideoPanel extends StatelessWidget {
  const _PreviewVideoPanel({
    required this.lang, required this.style,
    required this.rendering, required this.renderMsg,
    required this.render, required this.renderId,
    required this.onLangChange, required this.onStyleChange,
    required this.onRender,
  });
  final String lang, style, renderMsg;
  final bool rendering;
  final VideoRender? render;
  final String? renderId;
  final ValueChanged<String> onLangChange, onStyleChange;
  final VoidCallback onRender;

  static const _langs = {
    'en': 'English', 'en-in': 'English (India)', 'hi': 'Hindi',
    'ta': 'Tamil', 'te': 'Telugu', 'bn': 'Bengali', 'gu': 'Gujarati',
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        const Row(children: [
          Icon(Icons.movie_creation_outlined, size: 15,
              color: Color(0xFF7C3AED)),
          SizedBox(width: 6),
          Text('Generate Teaching Video', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: AColors.ink)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Language: ', style: TextStyle(
                fontSize: 12, color: AColors.textMuted)),
            DropdownButton<String>(
              value: lang, isDense: true, underline: const SizedBox(),
              items: _langs.entries.map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value,
                      style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: rendering
                  ? null : (v) { if (v != null) onLangChange(v); },
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Style: ', style: TextStyle(
                fontSize: 12, color: AColors.textMuted)),
            DropdownButton<String>(
              value: style, isDense: true, underline: const SizedBox(),
              items: _styles.entries.map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value,
                      style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: rendering
                  ? null : (v) { if (v != null) onStyleChange(v); },
            ),
          ]),
        ]),
        const SizedBox(height: 10),
        if (rendering)
          const Row(children: [
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Rendering…', style: TextStyle(
                fontSize: 12, color: AColors.textMuted)),
          ])
        else ...[
          Row(children: [
            AButton(
              label: 'Render Video',
              icon: Icons.play_arrow_rounded,
              variant: AButtonVariant.dark, size: AButtonSize.sm,
              onPressed: onRender,
            ),
            if (render?.isCompleted == true) ...[
              const SizedBox(width: 8),
              AButton(
                label: 'Download MP4',
                icon: Icons.download_rounded,
                variant: AButtonVariant.ghost, size: AButtonSize.sm,
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
                  color: render?.isFailed == true
                      ? AColors.red : AColors.textMuted)),
            ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared form helpers
// ═════════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label, required this.selected, required this.onTap,
    this.sublabel,
  });
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: sublabel != null ? 10 : 8),
        decoration: BoxDecoration(
          color: selected ? AColors.ink : AColors.bg2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AColors.ink : AColors.cardBorder),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AColors.textSecond)),
          if (sublabel != null)
            Text(sublabel!, style: TextStyle(
                fontSize: 10,
                color: selected ? Colors.white54 : AColors.textMuted)),
        ]),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: AColors.ink));
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 14, color: AColors.textMuted),
      const SizedBox(width: 6),
      SizedBox(width: 72, child: Text(label,
          style: const TextStyle(
              fontSize: 12, color: AColors.textMuted))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: AColors.ink),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ── Render status row (used in step 7) ────────────────────────────────────
class _RenderStatusRow extends StatelessWidget {
  const _RenderStatusRow({
    required this.title,
    required this.subtitle,
    required this.status,
  });
  final String title, subtitle, status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AColors.cardBorder),
      ),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(subtitle, style: const TextStyle(
              fontSize: 11, color: AColors.textMuted)),
        ])),
        const SizedBox(width: 12),
        _StatusChip(status),
      ]),
    );
  }
}

// ── Status chip (used in steps 7 & 8) ─────────────────────────────────────
class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    final bool spin;

    switch (status) {
      case 'queued':
        bg = const Color(0xFFE5E7EB); fg = AColors.textMuted;
        label = 'Queued'; spin = false;
      case 'rendering':
        bg = const Color(0xFFFFF3E0); fg = const Color(0xFFE65100);
        label = 'Rendering'; spin = true;
      case 'completed':
        bg = const Color(0xFFE8F5E9); fg = const Color(0xFF2E7D32);
        label = 'Done'; spin = false;
      case 'failed':
        bg = const Color(0xFFFFEBEE); fg = const Color(0xFFC62828);
        label = 'Failed'; spin = false;
      default:
        bg = const Color(0xFFFFF3E0); fg = const Color(0xFFE65100);
        label = status; spin = false;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (spin) ...[
          SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: fg),
          ),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

// ── Review stat (step 8 summary) ──────────────────────────────────────────
class _ReviewStat extends StatelessWidget {
  const _ReviewStat(this.value, this.label, this.color);
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(children: [
      Text(value, style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(
          fontSize: 11, color: color.withValues(alpha: 0.8))),
    ]),
  );
}

// ── Publish chip (step 9 summary card) ────────────────────────────────────
class _PublishChip extends StatelessWidget {
  const _PublishChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.9)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
    ]),
  );
}

// ── Action tile (step 9 action buttons) ───────────────────────────────────
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AColors.cardBorder),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(
            fontSize: 11, color: AColors.textMuted),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}
