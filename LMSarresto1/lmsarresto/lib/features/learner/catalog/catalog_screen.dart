import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/api/models.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_badge.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _search = '';
  String _category = 'All';
  static const _cats = ['All', 'FALL PROTECTION', 'EQUIPMENT', 'EMERGENCY', 'SITE SAFETY'];

  @override
  Widget build(BuildContext context) {
    final libAsync = ref.watch(libraryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Course Catalog', style: AText.h1()),
        const SizedBox(height: 2),
        Text('Explore all available safety training courses', style: AText.body()),
        const SizedBox(height: 24),

        // Search
        TextField(
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Search courses…',
            prefixIcon: const Icon(Icons.search_rounded, color: AColors.textMuted, size: 20),
            filled: true, fillColor: AColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AColors.cardBorder)),
          ),
        ),
        const SizedBox(height: 14),

        // Category filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _cats.map((cat) {
            final sel = _category == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _category = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? AColors.ink : AColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? AColors.ink : AColors.cardBorder),
                  ),
                  child: Text(cat, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AColors.textMuted)),
                ),
              ),
            );
          }).toList()),
        ),
        const SizedBox(height: 24),

        libAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (items) {
            var filtered = items.where((i) {
              final matchCat = _category == 'All' || i.category == _category;
              final matchSearch = _search.isEmpty || i.courseTitle.toLowerCase().contains(_search);
              return matchCat && matchSearch;
            }).toList();

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
                crossAxisCount: 3, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.72),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _CatalogCard(item: filtered[i]),
            );
          },
        ),
      ]),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item});
  final LibraryItem item;

  static const _catColors = <String, (Color, Color, IconData)>{
    'FALL PROTECTION': (Color(0xFFF97316), Color(0xFFEA580C), Icons.safety_check_rounded),
    'EQUIPMENT':       (Color(0xFF3B82F6), Color(0xFF1D4ED8), Icons.construction_rounded),
    'EMERGENCY':       (Color(0xFFEF4444), Color(0xFFB91C1C), Icons.medical_services_rounded),
    'SITE SAFETY':     (Color(0xFF22C55E), Color(0xFF15803D), Icons.verified_user_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final cats = _catColors[item.category] ?? _catColors['SITE SAFETY']!;

    return GestureDetector(
      onTap: () => context.go('/learner/catalog/${item.scriptId}'),
      child: Container(
        decoration: BoxDecoration(
          color: AColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AColors.cardBorder),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Card header with gradient
          Container(
            height: 130,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cats.$1, cats.$2],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15), topRight: Radius.circular(15)),
            ),
            child: Stack(children: [
              // Subtle decorative circle
              Positioned(
                right: -20, top: -20,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Center(child: Icon(cats.$3, size: 44, color: Colors.white.withValues(alpha: 0.92))),
            ]),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.category, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: cats.$1, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              Text(item.courseTitle, style: AText.bodyBold(),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Row(children: [
                const Icon(Icons.play_lesson_outlined, size: 13, color: AColors.textMuted),
                const SizedBox(width: 4),
                Text('${item.totalLessons} lessons', style: AText.tiny()),
                const SizedBox(width: 10),
                const Icon(Icons.schedule_outlined, size: 13, color: AColors.textMuted),
                const SizedBox(width: 4),
                Text('${item.estimatedDurationMin}m', style: AText.tiny()),
              ]),
            ]),
          )),
        ]),
      ),
    );
  }
}
