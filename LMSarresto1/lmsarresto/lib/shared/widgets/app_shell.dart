import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/api_client.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.role, required this.child});
  final String role;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _tutorOpen = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isAdmin = widget.role == 'admin';

    return Scaffold(
      backgroundColor: AColors.bg,
      body: Stack(children: [
        Row(children: [
          _Sidebar(isAdmin: isAdmin),
          Expanded(
            child: Column(children: [
              _Header(auth: auth, onSwitchRole: () {
                ref.read(authProvider.notifier).switchRole(isAdmin ? 'learner' : 'admin');
                context.go(isAdmin ? '/learner' : '/admin');
              }),
              Expanded(child: widget.child),
            ]),
          ),
        ]),
        // Floating Arresto AI button
        Positioned(
          right: 24, bottom: 24,
          child: _TutorFab(open: _tutorOpen, onToggle: () => setState(() => _tutorOpen = !_tutorOpen)),
        ),
        if (_tutorOpen)
          Positioned(
            right: 24, bottom: 88,
            child: _TutorPanel(onClose: () => setState(() => _tutorOpen = false)),
          ),
      ]),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    final navItems = isAdmin ? _adminNav : _learnerNav;

    return Container(
      width: 240,
      color: AColors.ink,
      child: Column(children: [
        // Logo
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: AColors.amber, borderRadius: BorderRadius.circular(6)),
              child: const Center(child: Text('A', style: TextStyle(
                  color: AColors.ink, fontWeight: FontWeight.w800, fontSize: 16))),
            ),
            const SizedBox(width: 10),
            const Text('Arresto LMS', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
        const Divider(color: AColors.sidebarDivider, height: 1),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12), children: [
            for (final section in navItems) ...[
              if (section.label != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                  child: Text(section.label!,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Color(0xFF8A8A8E), letterSpacing: 1.0)),
                ),
              for (final item in section.items)
                _SidebarItem(item: item, active: loc.startsWith(item.route)),
            ],
          ]),
        ),
        const Divider(color: AColors.sidebarDivider, height: 1),
        _SidebarFooter(),
      ]),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.active});
  final _NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? AColors.amber.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (item.externalUrl != null) {
              launchUrl(Uri.parse(item.externalUrl!), mode: LaunchMode.externalApplication);
            } else {
              context.go(item.route);
            }
          },
          hoverColor: Colors.white.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(item.icon, size: 17,
                  color: active ? AColors.amber : const Color(0xFF8A8A8E)),
              const SizedBox(width: 10),
              Expanded(child: Text(item.label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: active ? Colors.white : const Color(0xFFBBBBBE)))),
              if (item.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AColors.red, borderRadius: BorderRadius.circular(10)),
                  child: Text(item.badge!, style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AColors.amber,
          child: Text(user?.initials ?? '?',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.ink)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.name ?? '', style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          Text(user?.role ?? '', style: const TextStyle(
              fontSize: 11, color: Color(0xFF8A8A8E))),
        ])),
        IconButton(
          icon: const Icon(Icons.logout, size: 16, color: Color(0xFF8A8A8E)),
          onPressed: () {
            ref.read(authProvider.notifier).logout();
            context.go('/login');
          },
          tooltip: 'Sign out',
        ),
      ]),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.auth, required this.onSwitchRole});
  final AuthState auth;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AColors.surface,
        border: Border(bottom: BorderSide(color: AColors.cardBorder)),
      ),
      child: Row(children: [
        Text(_routeTitle(loc), style: AText.h3()),
        const Spacer(),
        // Role switcher pill
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AColors.bg2, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _RolePill(label: 'Learner', active: !auth.isAdmin, onTap: () {
              if (auth.isAdmin) onSwitchRole();
            }),
            _RolePill(label: 'Admin', active: auth.isAdmin, onTap: () {
              if (!auth.isAdmin) onSwitchRole();
            }),
          ]),
        ),
        const SizedBox(width: 16),
        // Avatar
        CircleAvatar(
          radius: 16,
          backgroundColor: AColors.amber,
          child: Text(auth.user?.initials ?? '?',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.ink)),
        ),
      ]),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: active ? Colors.white : AColors.textMuted)),
      ),
    );
  }
}

// ── Tutor FAB + Panel ──────────────────────────────────────────────────────────

class _TutorFab extends StatelessWidget {
  const _TutorFab({required this.open, required this.onToggle});
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AColors.ink, borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 24, height: 24,
            decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
            child: const Center(child: Text('AI', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w800, color: AColors.ink))),
          ),
          const SizedBox(width: 8),
          Text(open ? 'Close' : 'Arresto AI',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      ),
    );
  }
}

class _TutorPanel extends StatefulWidget {
  const _TutorPanel({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_TutorPanel> createState() => _TutorPanelState();
}

class _TutorPanelState extends State<_TutorPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [
    _Msg(role: 'assistant', text: 'Hi! I\'m Arresto AI — your safety training assistant. Ask me anything about your courses, safety procedures, or learning content.'),
  ];
  String? _sessionId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final data = await _createSession();
      if (mounted) setState(() => _sessionId = data);
    } catch (_) {}
  }

  Future<String> _createSession() async {
    // Lazy import to avoid circular deps
    final svc = _TutorSvcProxy();
    return svc.createSession();
  }

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(_Msg(role: 'user', text: txt));
      _busy = true;
    });
    _scrollBottom();

    try {
      final reply = await _TutorSvcProxy().chat(_sessionId ?? 'default', txt);
      if (mounted) {
        setState(() => _msgs.add(_Msg(role: 'assistant', text: reply)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _msgs.add(_Msg(role: 'assistant', text: 'Sorry, I encountered an error. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollBottom();
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360, height: 520,
      decoration: BoxDecoration(
        color: AColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AColors.cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AColors.ink,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
              child: const Center(child: Text('AI', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: AColors.ink))),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Arresto AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              Row(children: [
                CircleAvatar(radius: 3, backgroundColor: AColors.green),
                SizedBox(width: 5),
                Text('Online', style: TextStyle(color: Color(0xFF8A8A8E), fontSize: 11)),
              ]),
            ])),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white60, size: 18),
              onPressed: widget.onClose,
            ),
          ]),
        ),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length + (_busy ? 1 : 0),
            itemBuilder: (_, i) {
              if (_busy && i == _msgs.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(width: 8),
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Thinking…', style: TextStyle(fontSize: 12, color: AColors.textMuted)),
                  ]),
                );
              }
              final msg = _msgs[i];
              final isUser = msg.role == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isUser ? AColors.amber : AColors.bg2,
                    borderRadius: BorderRadius.circular(12),
                    border: isUser ? null : Border.all(color: AColors.cardBorder),
                  ),
                  child: isUser
                      ? Text(msg.text,
                          style: const TextStyle(fontSize: 13, color: AColors.ink))
                      : MarkdownBody(
                          data: msg.text,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 13, color: AColors.textPrimary, height: 1.4),
                            strong: const TextStyle(fontSize: 13, color: AColors.textPrimary, fontWeight: FontWeight.w700),
                            em: const TextStyle(fontSize: 13, color: AColors.textPrimary, fontStyle: FontStyle.italic),
                            listBullet: const TextStyle(fontSize: 13, color: AColors.textPrimary, height: 1.4),
                            code: const TextStyle(fontSize: 12, color: AColors.textSecond, fontFamily: 'monospace'),
                            codeblockDecoration: BoxDecoration(
                              color: AColors.bg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            blockSpacing: 6,
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        // Input
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AColors.cardBorder))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Ask anything…',
                  hintStyle: const TextStyle(fontSize: 13, color: AColors.textMuted),
                  filled: true,
                  fillColor: AColors.bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: AColors.amber, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, size: 16, color: AColors.ink),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Msg { final String role, text; _Msg({required this.role, required this.text}); }

// Uses /api/v1/chat (RAG Q&A) — no course context needed for the global assistant
class _TutorSvcProxy {
  Future<String> createSession() async => 'global';

  Future<String> chat(String sid, String question) async {
    final data = await ApiClient.post('/api/v1/chat', {'question': question});
    return (data as Map<String, dynamic>)['answer'] as String? ?? 'Sorry, no answer available.';
  }
}

// ── Route → page title ────────────────────────────────────────────────────────

String _routeTitle(String loc) {
  if (loc.startsWith('/admin/generator'))                                  return 'Course Generator';
  if (loc.startsWith('/admin/courses') && loc.split('/').length > 3)      return 'Course Detail';
  if (loc.startsWith('/admin/courses'))                                    return 'All Courses';
  if (loc.startsWith('/admin/learners'))                                   return 'Learners';
  if (loc.startsWith('/admin/analytics'))                                  return 'Analytics';
  if (loc.startsWith('/admin/support'))                                    return 'Support';
  if (loc.startsWith('/admin/settings'))                                   return 'Settings';
  if (loc.startsWith('/admin/studio'))                                     return 'Author Studio';
  if (loc.startsWith('/admin'))                                            return 'Dashboard';
  if (loc.startsWith('/learner/catalog') && loc.split('/').length > 3)    return 'Course Detail';
  if (loc.startsWith('/learner/catalog'))                                  return 'Course Catalog';
  if (loc.startsWith('/learner/lesson'))                                   return 'Lesson';
  if (loc.startsWith('/learner/play'))                                     return 'Course Player';
  if (loc.startsWith('/learner/assessments'))                              return 'Assessments';
  if (loc.startsWith('/learner/certificates'))                             return 'Certificates';
  if (loc.startsWith('/learner/support'))                                  return 'Help & Support';
  if (loc.startsWith('/learner'))                                          return 'Dashboard';
  return 'Arresto LMS';
}

// ── Navigation Data ────────────────────────────────────────────────────────────

class _NavSection {
  final String? label;
  final List<_NavItem> items;
  _NavSection({this.label, required this.items});
}

class _NavItem {
  final String label;
  final String route;
  final IconData icon;
  final String? badge;
  final String? externalUrl;
  _NavItem({required this.label, required this.route, required this.icon, this.badge, this.externalUrl});
}

final _adminNav = [
  _NavSection(label: 'MANAGEMENT', items: [
    _NavItem(label: 'Dashboard',        route: '/admin',           icon: Icons.grid_view_rounded),
    _NavItem(label: 'Course Generator', route: '/admin/generator', icon: Icons.auto_awesome_rounded),
    _NavItem(label: 'All Courses',      route: '/admin/courses',   icon: Icons.library_books_rounded),
    _NavItem(label: 'Learners',         route: '/admin/learners',  icon: Icons.people_rounded),
    _NavItem(label: 'Analytics',        route: '/admin/analytics', icon: Icons.bar_chart_rounded),
    _NavItem(label: 'Support',          route: '/admin/support',   icon: Icons.headset_mic_rounded),
    _NavItem(label: 'Settings',         route: '/admin/settings',  icon: Icons.settings_rounded),
  ]),
  _NavSection(label: 'TOOLS', items: [
    _NavItem(
      label: 'Author Studio',
      route: '/admin/studio',
      icon: Icons.video_camera_back_rounded,
    ),
  ]),
];

final _learnerNav = [
  _NavSection(label: 'LEARNING', items: [
    _NavItem(label: 'Dashboard',     route: '/learner',              icon: Icons.grid_view_rounded),
    _NavItem(label: 'Course Catalog',route: '/learner/catalog',      icon: Icons.explore_rounded),
    _NavItem(label: 'Assessments',   route: '/learner/assessments',  icon: Icons.quiz_rounded),
    _NavItem(label: 'Certificates',  route: '/learner/certificates', icon: Icons.workspace_premium_rounded),
  ]),
  _NavSection(label: 'HELP', items: [
    _NavItem(label: 'Help & Support', route: '/learner/support', icon: Icons.help_outline_rounded),
  ]),
];
