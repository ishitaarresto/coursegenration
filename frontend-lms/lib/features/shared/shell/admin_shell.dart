import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import 'app_header.dart';
import '../arresto_ai/arresto_ai_panel.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: ArrestoColors.background,
      floatingActionButton: const _AIFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isDesktop) const _AdminSidebar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AIFab extends StatelessWidget {
  const _AIFab();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: ArrestoColors.ink,
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const ArrestoAIPanel(),
      ),
      icon: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: ArrestoColors.amber,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.auto_awesome_rounded,
            size: 13, color: ArrestoColors.ink),
      ),
      label: Text('Arresto AI',
          style: ArrestoText.small(color: Colors.white)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar();

  @override
  Widget build(BuildContext context) {
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
                _sectionLabel('MANAGEMENT'),
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  route: '/admin',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Course Generator',
                  route: '/admin/generator',
                  location: location,
                  badge: '2',
                ),
                _NavItem(
                  icon: Icons.library_books_rounded,
                  label: 'All Courses',
                  route: '/admin/courses',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.videocam_rounded,
                  label: 'Video Studio',
                  route: '/admin/video',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.people_rounded,
                  label: 'Learners',
                  route: '/admin/learners',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'Analytics',
                  route: '/admin/analytics',
                  location: location,
                ),
                _NavItem(
                  icon: Icons.support_agent_rounded,
                  label: 'Support',
                  route: '/admin/support',
                  location: location,
                  badge: '3',
                ),
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  route: '/admin/settings',
                  location: location,
                ),
              ],
            ),
          ),
          Container(
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
                    color: ArrestoColors.orangeTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('AD',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ArrestoColors.orange)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Admin User',
                          style: ArrestoText.small(color: ArrestoColors.ink)
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      Text('Administrator',
                          style: ArrestoText.xs()),
                    ],
                  ),
                ),
              ],
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
  final String? badge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.location,
    this.badge,
  });

  bool get _active =>
      location == route || (route != '/admin' && location.startsWith(route));

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
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          _active ? FontWeight.w700 : FontWeight.w500,
                      color: _active
                          ? ArrestoColors.orange
                          : ArrestoColors.textSecondary,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: ArrestoColors.orange,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(badge!,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
