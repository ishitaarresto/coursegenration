import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/colors.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/api/models.dart';
import '../../../core/api/course_service.dart';
import '../../../shared/widgets/arresto_button.dart';

class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});
  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All Courses', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
            Text('Manage your course library', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
          ])),
          AButton(
            label: 'Generate Course',
            icon: Icons.add_rounded,
            onPressed: () => context.go('/admin/generator'),
          ),
        ]),
        const SizedBox(height: 24),

        // Search
        TextField(
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Search courses…',
            prefixIcon: const Icon(Icons.search_rounded, color: AColors.textMuted, size: 20),
            filled: true,
            fillColor: AColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AColors.cardBorder)),
          ),
        ),
        const SizedBox(height: 20),

        libraryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e', style: const TextStyle(color: AColors.red)),
          data: (items) {
            final filtered = _search.isEmpty ? items
                : items.where((i) => i.courseTitle.toLowerCase().contains(_search)
                    || i.sourceFile.toLowerCase().contains(_search)).toList();

            if (filtered.isEmpty) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('No courses found', style: TextStyle(color: AColors.textMuted)),
              ));
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 16, mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _CourseCard(item: filtered[i], ref: ref),
            );
          },
        ),
      ]),
    );
  }
}

class _CourseCard extends StatefulWidget {
  const _CourseCard({required this.item, required this.ref});
  final LibraryItem item;
  final WidgetRef ref;
  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _deleting = false;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Course?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AColors.ink)),
        content: Text(
          'Remove "${widget.item.courseTitle}" from the library?\n\nThis cannot be undone.',
          style: const TextStyle(fontSize: 13, color: AColors.textSecond, height: 1.5),
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
      await CourseService.deleteScript(widget.item.scriptId);
      await widget.ref.read(libraryProvider.notifier).refresh();
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dt = DateTime.fromMillisecondsSinceEpoch((item.generatedAt * 1000).toInt());
    final dateStr = DateFormat('MMM d, yyyy').format(dt);
    final cats = _catColors[item.category] ?? _catColors['SITE SAFETY']!;

    return Stack(children: [
      GestureDetector(
        onTap: () => context.go('/admin/courses/${item.scriptId}'),
        child: Container(
          decoration: BoxDecoration(
            color: _deleting ? AColors.bg2 : AColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AColors.cardBorder),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Thumbnail
            Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cats.$1, cats.$2],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15), topRight: Radius.circular(15)),
              ),
              child: Center(child: _deleting
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Icon(cats.$3, size: 40, color: Colors.white.withValues(alpha: 0.9))),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.category, style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: AColors.textMuted, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  Text(item.courseTitle, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AColors.ink),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  Row(children: [
                    const Icon(Icons.play_lesson_outlined, size: 13, color: AColors.textMuted),
                    const SizedBox(width: 4),
                    Text('${item.totalLessons} lessons',
                        style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
                    const SizedBox(width: 10),
                    const Icon(Icons.schedule_outlined, size: 13, color: AColors.textMuted),
                    const SizedBox(width: 4),
                    Text('${item.estimatedDurationMin}m',
                        style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
                  ]),
                  const SizedBox(height: 8),
                  Text('Generated $dateStr',
                      style: const TextStyle(fontSize: 10, color: AColors.textMuted2)),
                ]),
              ),
            ),
          ]),
        ),
      ),
      // Delete button — top right corner
      if (!_deleting)
        Positioned(
          top: 8, right: 8,
          child: GestureDetector(
            onTap: () => _confirmDelete(context),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 15),
            ),
          ),
        ),
    ]);
  }
}

const _catColors = <String, (Color, Color, IconData)>{
  'FALL PROTECTION': (Color(0xFFF97316), Color(0xFFEA580C), Icons.safety_check_rounded),
  'EQUIPMENT':       (Color(0xFF3B82F6), Color(0xFF1D4ED8), Icons.construction_rounded),
  'EMERGENCY':       (Color(0xFFEF4444), Color(0xFFB91C1C), Icons.medical_services_rounded),
  'SITE SAFETY':     (Color(0xFF22C55E), Color(0xFF15803D), Icons.verified_user_rounded),
};
