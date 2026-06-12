import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/api/models.dart';
import '../../../core/api/course_service.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_button.dart';

class LearnerCourseDetailScreen extends StatefulWidget {
  const LearnerCourseDetailScreen({super.key, required this.scriptId});
  final String scriptId;
  @override
  State<LearnerCourseDetailScreen> createState() => _State();
}

class _State extends State<LearnerCourseDetailScreen> {
  CourseScript? _script;
  bool _loading = true;
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    final s = _script!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Main content
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
            if (s.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(s.description, style: const TextStyle(fontSize: 14, color: AColors.textSecond)),
            ],
            const SizedBox(height: 24),

            if (s.objectives.isNotEmpty) ...[
              APanel(
                title: 'What you\'ll learn',
                child: Column(children: s.objectives.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 16, color: AColors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(o, style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
                  ]),
                )).toList()),
              ),
              const SizedBox(height: 20),
            ],

            // Module list
            APanel(
              title: 'Course Content',
              subtitle: s.isCustom ? '${s.items.length} items' : '${s.modules.length} modules',
              child: Column(children: s.isCustom
                  ? s.items.asMap().entries.map((e) => _ItemRow(e.value, e.key, widget.scriptId)).toList()
                  : s.modules.map((m) => _ModuleSection(m, widget.scriptId)).toList()),
            ),
          ]),
        ),
        const SizedBox(width: 24),

        // Sidebar
        SizedBox(
          width: 280,
          child: ACard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEA580C)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Icon(Icons.school_rounded, size: 56, color: Colors.white60)),
              ),
              const SizedBox(height: 16),
              Text(s.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.ink),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              _InfoRow(Icons.play_lesson_outlined,
                  s.isCustom ? '${s.items.length} items' : '${s.modules.fold(0, (n, m) => n + m.lessons.length)} lessons'),
              const SizedBox(height: 16),
              AButton(label: 'Start Learning', onPressed: () {
                if (s.isCustom && s.items.isNotEmpty) {
                  context.go('/learner/play/${widget.scriptId}/0');
                } else if (!s.isCustom && s.modules.isNotEmpty && s.modules.first.lessons.isNotEmpty) {
                  final m = s.modules.first;
                  final l = m.lessons.first;
                  context.go('/learner/lesson/${widget.scriptId}/m${m.moduleNumber}_l${l.lessonNumber}');
                }
              }, fullWidth: true),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ModuleSection extends StatelessWidget {
  const _ModuleSection(this.module, this.scriptId);
  final CourseModule module;
  final String scriptId;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text('Module ${module.moduleNumber}: ${module.title}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.ink)),
      ),
      ...module.lessons.map((l) => InkWell(
        onTap: () => context.go('/learner/lesson/$scriptId/m${module.moduleNumber}_l${l.lessonNumber}'),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Row(children: [
            const Icon(Icons.play_circle_outline_rounded, size: 16, color: AColors.textMuted),
            const SizedBox(width: 8),
            Expanded(child: Text('${l.lessonNumber}. ${l.title}',
                style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
          ]),
        ),
      )),
      const SizedBox(height: 8),
    ]);
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.item, this.index, this.scriptId);
  final CourseItem item;
  final int index;
  final String scriptId;

  @override
  Widget build(BuildContext context) {
    final isQuiz = item.type == 'quiz';
    return InkWell(
      onTap: () => context.go('/learner/play/$scriptId/$index'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: isQuiz ? AColors.amberSoft : AColors.bg2,
              shape: BoxShape.circle,
            ),
            child: Center(child: Icon(
              isQuiz ? Icons.quiz_outlined : Icons.article_outlined,
              size: 14,
              color: isQuiz ? AColors.orange : AColors.textMuted,
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(item.title, style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
          const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AColors.textMuted2),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: AColors.textMuted),
    const SizedBox(width: 6),
    Text(text, style: const TextStyle(fontSize: 12, color: AColors.textMuted)),
  ]);
}
