import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/providers/app_state.dart';
import '../../../data/providers/api_providers.dart';
import '../notifications/notification_panel.dart';

class AppHeader extends ConsumerStatefulWidget {
  const AppHeader({super.key});

  @override
  ConsumerState<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends ConsumerState<AppHeader> {
  final _notifController = OverlayPortalController();
  final _profileController = OverlayPortalController();
  final _notifLink = LayerLink();
  final _profileLink = LayerLink();

  void _toggleNotif() {
    if (_profileController.isShowing) _profileController.hide();
    if (_notifController.isShowing) {
      _notifController.hide();
    } else {
      _notifController.show();
    }
  }

  void _toggleProfile() {
    if (_notifController.isShowing) _notifController.hide();
    if (_profileController.isShowing) {
      _profileController.hide();
    } else {
      _profileController.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleProvider);
    final learnerId = ref.watch(learnerIdProvider);
    final profileAsync = ref.watch(profileProvider(learnerId));
    final displayName = profileAsync.valueOrNull?.displayName ?? learnerId;

    final recipientId = role == UserRole.admin ? 'admin' : learnerId;
    final notifsAsync = ref.watch(notificationsProvider(recipientId));
    final unread = notifsAsync.valueOrNull?.where((n) => !n.read).length ?? 0;

    return Container(
      height: ArrestoSpacing.headerHeight,
      decoration: const BoxDecoration(
        color: ArrestoColors.surface,
        border: Border(bottom: BorderSide(color: ArrestoColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _ArrestoLogo(),
          const Spacer(),
          _RoleSwitcher(role: role),
          const SizedBox(width: 16),

          // ── Notification Bell ──────────────────────────────
          CompositedTransformTarget(
            link: _notifLink,
            child: OverlayPortal(
              controller: _notifController,
              overlayChildBuilder: (ctx) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _notifController.hide,
                    ),
                  ),
                  CompositedTransformFollower(
                    link: _notifLink,
                    targetAnchor: Alignment.bottomRight,
                    followerAnchor: Alignment.topRight,
                    offset: const Offset(0, 4),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: const NotificationPanel(),
                    ),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded, size: 22),
                    color: ArrestoColors.ink,
                    onPressed: _toggleNotif,
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IgnorePointer(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: ArrestoColors.red,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 4),

          // ── Profile Avatar ──────────────────────────────────
          CompositedTransformTarget(
            link: _profileLink,
            child: OverlayPortal(
              controller: _profileController,
              overlayChildBuilder: (ctx) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _profileController.hide,
                    ),
                  ),
                  CompositedTransformFollower(
                    link: _profileLink,
                    targetAnchor: Alignment.bottomRight,
                    followerAnchor: Alignment.topRight,
                    offset: const Offset(0, 4),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: _ProfileDropdown(
                        onClose: _profileController.hide,
                        role: role,
                        displayName: displayName,
                      ),
                    ),
                  ),
                ],
              ),
              child: GestureDetector(
                onTap: _toggleProfile,
                child: ArrestoAvatar(name: displayName, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile dropdown ───────────────────────────────────────────────────────────

class _ProfileDropdown extends StatelessWidget {
  final VoidCallback onClose;
  final UserRole role;
  final String displayName;
  const _ProfileDropdown({required this.onClose, required this.role, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: ArrestoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ArrestoColors.cardBorder),
        boxShadow: ArrestoColors.sh4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ArrestoAvatar(name: displayName, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: ArrestoText.bodyBold()),
                      Text(
                        role == UserRole.admin ? 'Administrator' : 'Learner',
                        style: ArrestoText.xs(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ArrestoColors.line),
          _item(context, Icons.person_rounded, 'My Profile', () {
            onClose();
            context.go('/learner/profile');
          }),
          _item(context, Icons.settings_rounded, 'Settings', () {
            onClose();
            context.go(role == UserRole.admin ? '/admin/settings' : '/learner/profile');
          }),
          _item(context, Icons.help_outline_rounded, 'Help & Support', () {
            onClose();
            context.go('/learner/support');
          }),
          const Divider(height: 1, color: ArrestoColors.line),
          _item(context, Icons.logout_rounded, 'Sign Out', () {
            onClose();
            context.go('/learner');
          }, color: ArrestoColors.red),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _item(BuildContext ctx, IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? ArrestoColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 10),
            Text(label, style: ArrestoText.body(color: c)),
          ]),
        ),
      ),
    );
  }
}

// ── Logo ───────────────────────────────────────────────────────────────────────

class _ArrestoLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: ArrestoColors.amber,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Center(
            child: Text('A',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: ArrestoColors.ink)),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('ARRESTO',
                style: ArrestoText.eyebrow(color: ArrestoColors.ink)
                    .copyWith(letterSpacing: 2)),
            Text('LMS',
                style: ArrestoText.xs(color: ArrestoColors.textMuted)
                    .copyWith(letterSpacing: 1)),
          ],
        ),
      ],
    );
  }
}

// ── Role switcher ──────────────────────────────────────────────────────────────

class _RoleSwitcher extends ConsumerWidget {
  final UserRole role;
  const _RoleSwitcher({required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: ArrestoColors.bg2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ArrestoColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill('Learner', UserRole.learner, role, ref, context),
          _pill('Admin', UserRole.admin, role, ref, context),
        ],
      ),
    );
  }

  Widget _pill(String label, UserRole val, UserRole current, WidgetRef ref,
      BuildContext ctx) {
    final active = current == val;
    return GestureDetector(
      onTap: () {
        ref.read(roleProvider.notifier).state = val;
        ctx.go(val == UserRole.learner ? '/learner' : '/admin');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ArrestoColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : ArrestoColors.textMuted,
          ),
        ),
      ),
    );
  }
}
