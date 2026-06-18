import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import 'app_header.dart';
import '../arresto_ai/arresto_ai_panel.dart';
import '../../../core/widgets/arresto_ai_logo.dart';

class LearnerShell extends ConsumerWidget {
  final Widget child;
  const LearnerShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final isMobile = MediaQuery.of(context).size.width < 640;

    return Scaffold(
      backgroundColor: ArrestoColors.background,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: Row(
              children: [
                if (isDesktop) const _LearnerSidebar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile ? const _LearnerBottomNav() : null,
      floatingActionButton: const _AIFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _LearnerSidebar extends ConsumerWidget {
  const _LearnerSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();

    return Container(
      width: ArrestoSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: ArrestoColors.surface,
        border: Border(right: BorderSide(color: ArrestoColors.cardBorder)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              children: [
                _sectionLabel('LEARNING'),
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  route: '/learner',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.explore_rounded,
                  label: 'Course Catalog',
                  route: '/learner/catalog',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.school_rounded,
                  label: 'My Courses',
                  route: '/learner/my-courses',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.assignment_rounded,
                  label: 'Assessments',
                  route: '/learner/assessments',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Certificates',
                  route: '/learner/certificates',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.folder_open_rounded,
                  label: 'Resources',
                  route: '/learner/resources',
                  location: location,
                ),
                const SizedBox(height: 8),
                _sectionLabel('HELP'),
                _NavItem(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & Support',
                  route: '/learner/support',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Arresto AI',
                  route: '/learner/ai',
                  location: location,
                ),
              ],
            ),
          ),
          // User info bottom
          GestureDetector(
            onTap: () => context.go('/learner/profile'),
            child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ArrestoColors.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ArrestoColors.amberSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('JH',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('James Harrington',
                          style: ArrestoText.small(color: ArrestoColors.ink)
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      Text('Learner',
                          style: ArrestoText.xs()),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => context.go('/learner/profile'),
                  child: const Icon(Icons.settings_rounded,
                      size: 16, color: ArrestoColors.textMuted),
                ),
              ],
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: ArrestoColors.textMuted2,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final String location;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.location,
  });

  bool get _active =>
      location == route || (route != '/learner' && location.startsWith(route));

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: _active ? ArrestoColors.amberSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: _active
                      ? ArrestoColors.orange
                      : ArrestoColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _active ? FontWeight.w700 : FontWeight.w500,
                    color: _active
                        ? ArrestoColors.orange
                        : ArrestoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LearnerBottomNav extends StatelessWidget {
  const _LearnerBottomNav();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return NavigationBar(
      backgroundColor: ArrestoColors.surface,
      indicatorColor: ArrestoColors.amberSoft,
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home'),
        NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Catalog'),
        NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Assess'),
        NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium_rounded),
            label: 'Certs'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile'),
      ],
      selectedIndex: _indexFromLocation(location),
      onDestinationSelected: (i) {
        switch (i) {
          case 0: context.go('/learner');
          case 1: context.go('/learner/catalog');
          case 2: context.go('/learner/assessment/c1');
          case 3: context.go('/learner/certificates');
          case 4: context.go('/learner/profile');
        }
      },
    );
  }

  int _indexFromLocation(String loc) {
    if (loc.startsWith('/learner/catalog')) return 1;
    if (loc.startsWith('/learner/assessment')) return 2;
    if (loc.startsWith('/learner/certificates')) return 3;
    if (loc.startsWith('/learner/profile')) return 4;
    return 0;
  }
}

class _AIFab extends StatelessWidget {
  const _AIFab();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    // Lesson player has its own AI button; /learner/ai renders the full panel inline.
    if (location.contains('/lesson/') || location == '/learner/ai') {
      return const SizedBox.shrink();
    }

    return FloatingActionButton.extended(
      backgroundColor: ArrestoColors.ink,
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const ArrestoAIPanel(),
      ),
      icon: const ArrestoAiLogo(size: 24),
      label: Text('Arresto AI',
          style: ArrestoText.small(color: Colors.white)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
