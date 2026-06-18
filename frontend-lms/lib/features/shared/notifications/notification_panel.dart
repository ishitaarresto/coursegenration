import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/providers/api_providers.dart';
import '../../../data/providers/app_state.dart';

class NotificationPanel extends ConsumerWidget {
  const NotificationPanel({super.key});

  String _recipientId(WidgetRef ref) {
    final role     = ref.read(roleProvider);
    final learnerId = ref.read(learnerIdProvider);
    return role == UserRole.admin ? 'admin' : learnerId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role      = ref.watch(roleProvider);
    final learnerId = ref.watch(learnerIdProvider);
    final recipientId = role == UserRole.admin ? 'admin' : learnerId;
    final asyncNotifs = ref.watch(notificationsProvider(recipientId));

    return Container(
      width: 380,
      constraints: const BoxConstraints(maxHeight: 480),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Text('Notifications', style: ArrestoText.h3()),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await NotificationService.markAllRead(_recipientId(ref));
                    ref.invalidate(notificationsProvider(_recipientId(ref)));
                  },
                  child: Text(
                    'Mark all read',
                    style: ArrestoText.small(color: ArrestoColors.orange)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ArrestoColors.line),
          asyncNotifs.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Could not load notifications.',
                    style: ArrestoText.small()),
              ),
            ),
            data: (notifications) {
              if (notifications.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('No notifications yet.',
                        style: ArrestoText.small(
                            color: ArrestoColors.textMuted)),
                  ),
                );
              }
              return Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: ArrestoColors.line),
                  itemBuilder: (ctx, i) {
                    final n = notifications[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      onTap: n.read
                          ? null
                          : () async {
                              await NotificationService.markRead(n.id);
                              ref.invalidate(
                                  notificationsProvider(recipientId));
                            },
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: n.read
                              ? ArrestoColors.bg2
                              : ArrestoColors.amberSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(n.icon,
                            style: const TextStyle(fontSize: 16)),
                      ),
                      title: Text(
                        n.title,
                        style: ArrestoText.bodyMd(
                            color: n.read
                                ? ArrestoColors.textMuted
                                : ArrestoColors.ink),
                      ),
                      subtitle: Text(
                        n.body,
                        style:
                            ArrestoText.xs(color: ArrestoColors.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(n.time, style: ArrestoText.xs()),
                          if (!n.read)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: ArrestoColors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
