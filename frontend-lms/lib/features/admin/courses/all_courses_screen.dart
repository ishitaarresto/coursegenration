import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/chip_group.dart';
import '../../../core/widgets/course_thumb.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/services/course_service.dart';
import '../../../core/services/video_service.dart';
import '../../../data/models/course.dart';
import '../../../data/providers/api_providers.dart';

class AllCoursesScreen extends ConsumerStatefulWidget {
  const AllCoursesScreen({super.key});

  @override
  ConsumerState<AllCoursesScreen> createState() => _AllCoursesScreenState();
}

class _AllCoursesScreenState extends ConsumerState<AllCoursesScreen> {
  String _search   = '';
  String _status   = 'All';
  String _viewMode = 'Grid';

  void _view(BuildContext ctx, Course course) {
    ctx.go('/learner/course/${course.id}');
  }

  Future<void> _generateVideos(BuildContext ctx, Course course) async {
    final style = await showDialog<String>(
      context: ctx,
      builder: (dctx) => _GenerateVideoDialog(course: course),
    );
    if (style == null || !ctx.mounted) return;
    try {
      final count = await VideoService.generateAll(course.id, style: style);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(
            'Generating $count video${count != 1 ? 's' : ''} for "${course.title}". '
            'This may take a few minutes per lesson.',
          ),
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Video generation failed: $e'),
          backgroundColor: ArrestoColors.red,
        ));
      }
    }
  }

  void _showEditSheet(BuildContext ctx, Course course) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCourseSheet(
        course: course,
        onSaved: () => ref.invalidate(libraryProvider),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, Course course) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete Course'),
        content: Text('Delete "${course.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: TextButton.styleFrom(foregroundColor: ArrestoColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      await CourseService.deleteScript(course.id);
      ref.invalidate(libraryProvider);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    return Scaffold(
      backgroundColor: ArrestoColors.background,
      body: libraryAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ArrestoColors.orange),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wifi_off_rounded,
                  color: ArrestoColors.textMuted2, size: 40),
              const SizedBox(height: 12),
              Text('Could not load courses', style: ArrestoText.bodyMd()),
              const SizedBox(height: 4),
              Text('$e', style: ArrestoText.small(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ArrestoButton(
                label: 'Retry',
                size: ArrestoButtonSize.sm,
                onPressed: () => ref.invalidate(libraryProvider),
              ),
            ]),
          ),
        ),
        data: (all) => _buildContent(context, all),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Course> all) {
    final filtered = all.where((c) {
      final matchSearch = _search.isEmpty ||
          c.title.toLowerCase().contains(_search.toLowerCase()) ||
          c.code.toLowerCase().contains(_search.toLowerCase());
      final matchStatus = _status == 'All' || c.status == _status.toLowerCase();
      return matchSearch && matchStatus;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: SectionHeader(
                      icon: Icons.library_books_rounded,
                      title: 'All Courses',
                      subtitle:
                          '${all.length} courses · ${all.where((c) => c.status == 'published').length} published',
                    ),
                  ),
                  ArrestoButton(
                    label: 'Generate New',
                    icon: const Icon(Icons.auto_awesome_rounded),
                    size: ArrestoButtonSize.sm,
                    onPressed: () => context.go('/admin/generator'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: ArrestoColors.textMuted),
                    tooltip: 'Refresh',
                    onPressed: () => ref.invalidate(libraryProvider),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  _statChip('${all.length}', 'Total', ArrestoColors.ink),
                  const SizedBox(width: 8),
                  _statChip(
                      '${all.where((c) => c.status == 'published').length}',
                      'Published', ArrestoColors.green),
                  const SizedBox(width: 8),
                  _statChip(
                      '${all.where((c) => c.status == 'draft').length}',
                      'Draft', ArrestoColors.amber),
                  const SizedBox(width: 8),
                  _statChip(
                      '${all.where((c) => c.status == 'generating').length}',
                      'Generating', ArrestoColors.orange),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded,
                            color: ArrestoColors.textMuted),
                        hintText: 'Search by title or code…',
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(999))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ChipGroup(
                    options: const ['All', 'Published', 'Draft'],
                    selected: _status,
                    onChanged: (v) => setState(() => _status = v),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: ArrestoColors.bg2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ArrestoColors.line),
                    ),
                    child: Row(children: [
                      _viewBtn(Icons.grid_view_rounded, 'Grid'),
                      _viewBtn(Icons.table_rows_rounded, 'Table'),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Text('${filtered.length} results', style: ArrestoText.small()),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        if (filtered.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_books_outlined,
                      color: ArrestoColors.textMuted2, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    all.isEmpty
                        ? 'No courses generated yet.\nUse "Generate New" to create your first course.'
                        : 'No courses match your search.',
                    style: ArrestoText.body(),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (_viewMode == 'Grid')
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid.builder(
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.68,
              ),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => _AdminCourseCard(
                course: filtered[i],
                onView: () => _view(ctx, filtered[i]),
                onEdit: () => _showEditSheet(ctx, filtered[i]),
                onGenerateVideo: () => _generateVideos(ctx, filtered[i]),
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _CoursesTable(
                courses: filtered,
                onEdit: (c) => _showEditSheet(context, c),
                onDelete: (c) => _confirmDelete(context, c),
                onGenerateVideo: (c) => _generateVideos(context, c),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _statChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 5),
        Text(label, style: ArrestoText.xs()),
      ]),
    );
  }

  Widget _viewBtn(IconData icon, String mode) {
    final active = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? ArrestoColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon,
            size: 16,
            color: active ? Colors.white : ArrestoColors.textMuted),
      ),
    );
  }
}

// ── Grid card ─────────────────────────────────────────────────────────────────

class _AdminCourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onGenerateVideo;

  const _AdminCourseCard({
    required this.course,
    required this.onView,
    required this.onEdit,
    required this.onGenerateVideo,
  });

  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      padding: EdgeInsets.zero,
      onTap: onView,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(15)),
            child: CourseThumb(style: course.style, code: course.code),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(course.cat,
                            style: ArrestoText.eyebrow(),
                            overflow: TextOverflow.ellipsis)),
                    StatusBadge(status: course.status),
                  ]),
                  const SizedBox(height: 4),
                  Text(course.title,
                      style: ArrestoText.h3(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.menu_book_rounded,
                        size: 12, color: ArrestoColors.textMuted),
                    const SizedBox(width: 3),
                    Text('${course.lessons} lessons', style: ArrestoText.small()),
                    const SizedBox(width: 10),
                    Icon(Icons.schedule_rounded,
                        size: 12, color: ArrestoColors.textMuted),
                    const SizedBox(width: 3),
                    Text('${course.mins} min', style: ArrestoText.small()),
                  ]),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: ArrestoButton(
                        label: 'Edit',
                        size: ArrestoButtonSize.sm,
                        variant: ArrestoButtonVariant.ghost,
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: onEdit,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ArrestoButton(
                        label: 'View',
                        size: ArrestoButtonSize.sm,
                        icon: const Icon(Icons.visibility_rounded),
                        onPressed: onView,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ArrestoButton(
                      label: 'Generate Videos',
                      size: ArrestoButtonSize.sm,
                      variant: ArrestoButtonVariant.ghost,
                      icon: const Icon(Icons.video_library_rounded),
                      onPressed: onGenerateVideo,
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
}

// ── Table view ────────────────────────────────────────────────────────────────

class _CoursesTable extends StatelessWidget {
  final List<Course> courses;
  final void Function(Course) onEdit;
  final void Function(Course) onDelete;
  final void Function(Course) onGenerateVideo;

  const _CoursesTable({
    required this.courses,
    required this.onEdit,
    required this.onDelete,
    required this.onGenerateVideo,
  });

  @override
  Widget build(BuildContext context) {
    return ArrestoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: Text('Course', style: ArrestoText.smallBold())),
              Expanded(
                  child: Text('Lessons', style: ArrestoText.smallBold())),
              Expanded(
                  child: Text('Status', style: ArrestoText.smallBold())),
              Expanded(
                  child: Text('Duration', style: ArrestoText.smallBold())),
              const SizedBox(width: 120),
            ]),
          ),
          const Divider(height: 1, color: ArrestoColors.line),
          ...courses.map((c) => _TableRow(
                course: c,
                onEdit: () => onEdit(c),
                onDelete: () => onDelete(c),
                onGenerateVideo: () => onGenerateVideo(c),
              )),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final Course course;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onGenerateVideo;

  const _TableRow({
    required this.course,
    required this.onEdit,
    required this.onDelete,
    required this.onGenerateVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: ArrestoColors.line, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 36,
            height: 36,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CourseThumb(style: course.style, code: null, height: 36),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(course.title,
                  style: ArrestoText.bodyBold(),
                  overflow: TextOverflow.ellipsis),
              Text(course.code, style: ArrestoText.xs()),
            ]),
          ),
          Expanded(
              child: Text('${course.lessons}',
                  style: ArrestoText.body(color: ArrestoColors.ink))),
          Expanded(child: StatusBadge(status: course.status)),
          Expanded(
              child: Text('${course.mins} min', style: ArrestoText.small())),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.video_library_rounded,
                  size: 16, color: ArrestoColors.orange),
              onPressed: onGenerateVideo,
              tooltip: 'Generate Videos',
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  size: 16, color: ArrestoColors.textMuted),
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 16, color: ArrestoColors.textMuted),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Edit bottom sheet ─────────────────────────────────────────────────────────

class _EditCourseSheet extends StatefulWidget {
  final Course course;
  final VoidCallback onSaved;
  const _EditCourseSheet({required this.course, required this.onSaved});

  @override
  State<_EditCourseSheet> createState() => _EditCourseSheetState();
}

class _EditCourseSheetState extends State<_EditCourseSheet> {
  late final TextEditingController _titleCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.course.title);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newTitle = _titleCtrl.text.trim();
    if (newTitle.isEmpty) return;
    if (newTitle == widget.course.title) {
      Navigator.pop(context);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await CourseService.updateCourseTitle(widget.course.id, newTitle);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _saving = false; _error = 'Save failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: ArrestoColors.bg2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Course', style: ArrestoText.h2()),
          const SizedBox(height: 4),
          Text(widget.course.code, style: ArrestoText.xs()),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            enabled: !_saving,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Course Title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: ArrestoText.small(color: ArrestoColors.red)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: ArrestoButton(
                label: 'Cancel',
                variant: ArrestoButtonVariant.ghost,
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ArrestoButton(
                label: _saving ? 'Saving…' : 'Save',
                onPressed: _saving ? null : _save,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Generate video confirmation dialog ────────────────────────────────────────

class _GenerateVideoDialog extends StatefulWidget {
  final Course course;
  const _GenerateVideoDialog({required this.course});

  @override
  State<_GenerateVideoDialog> createState() => _GenerateVideoDialogState();
}

class _GenerateVideoDialogState extends State<_GenerateVideoDialog> {
  String _style = 'modern';

  // (style id, display name, description, icon, requires HeyGen)
  static const _options = <(String, String, String, IconData, bool)>[
    (
      'modern',
      'Free Animated',
      'No API key needed · Works always',
      Icons.movie_creation_rounded,
      false,
    ),
    (
      'animated_scene',
      'Animated Scene',
      'HeyGen AI · Requires HEYGEN_API_KEY in .env',
      Icons.auto_awesome_rounded,
      true,
    ),
    (
      'whiteboard_doodle',
      'Whiteboard Doodle',
      'HeyGen AI · Requires HEYGEN_API_KEY in .env',
      Icons.brush_rounded,
      true,
    ),
    (
      'hybrid',
      'Hybrid',
      'HeyGen AI · Mix of animated + live · Requires HEYGEN_API_KEY',
      Icons.layers_rounded,
      true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate Videos'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Course:', style: ArrestoText.small(color: ArrestoColors.textMuted)),
            Text(widget.course.title, style: ArrestoText.bodyBold()),
            const SizedBox(height: 16),
            Text('Choose video style', style: ArrestoText.smallBold()),
            const SizedBox(height: 8),
            ..._options.map((opt) {
              final selected = _style == opt.$1;
              return GestureDetector(
                onTap: () => setState(() => _style = opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? ArrestoColors.orangeTint : ArrestoColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? ArrestoColors.orange : ArrestoColors.line,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Radio<String>(
                      value: opt.$1,
                      groupValue: _style,
                      onChanged: (v) => setState(() => _style = v!),
                      activeColor: ArrestoColors.orange,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    Icon(opt.$4, size: 18,
                        color: selected ? ArrestoColors.orange : ArrestoColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(opt.$2, style: ArrestoText.bodyBold()),
                            if (opt.$5) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: ArrestoColors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('HeyGen',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: ArrestoColors.orange,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ]),
                          Text(opt.$3,
                              style: ArrestoText.xs(color: ArrestoColors.textMuted)),
                        ],
                      ),
                    ),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              'Already-completed videos are skipped. '
              'Failed renders will be retried. '
              'Jobs run in the background.',
              style: ArrestoText.small(color: ArrestoColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _style),
          icon: const Icon(Icons.video_library_rounded, size: 16),
          label: const Text('Generate'),
          style: FilledButton.styleFrom(backgroundColor: ArrestoColors.orange),
        ),
      ],
    );
  }
}
