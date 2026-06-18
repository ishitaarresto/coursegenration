import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/services/learner_service.dart';
import '../../../data/providers/api_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final learnerId    = ref.watch(learnerIdProvider);
    final profileAsync = ref.watch(profileProvider(learnerId));

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (_, __) => _buildContent(context, learnerId, null),
      data:    (p)     => _buildContent(context, learnerId, p),
    );
  }

  Widget _buildContent(BuildContext context, String learnerId, ProfileData? profile) {
    final name  = profile?.displayName ?? learnerId;
    final email = profile?.email       ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ArrestoCard(
            child: Column(
              children: [
                ArrestoAvatar(name: name, size: 72),
                const SizedBox(height: 12),
                Text(name,  style: ArrestoText.h2()),
                Text(email, style: ArrestoText.small()),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ArrestoButton(
                      label: 'Edit Profile',
                      size:  ArrestoButtonSize.sm,
                      onPressed: () => _showEditDialog(context, learnerId, name),
                    ),
                    const SizedBox(width: 8),
                    ArrestoButton(
                      label:   'Change Picture',
                      variant: ArrestoButtonVariant.ghost,
                      size:    ArrestoButtonSize.sm,
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:  Text('Picture upload coming soon.'),
                          duration: Duration(seconds: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              _stat('${profile?.enrolledCourses  ?? 0}', 'Enrolled'),
              const SizedBox(width: 12),
              _stat('${profile?.completedLessons ?? 0}', 'Completed'),
              const SizedBox(width: 12),
              _stat('${profile?.certificates     ?? 0}', 'Certificates'),
            ],
          ),
          const SizedBox(height: 16),

          ArrestoCard(
            child: Column(
              children: [
                _settingRow(Icons.person_rounded,        'My Profile'),
                _settingRow(Icons.lock_rounded,          'Change Password'),
                _settingRow(Icons.notifications_rounded, 'Notifications'),
                _settingRow(Icons.bar_chart_rounded,     'My Statistics'),
                const Divider(color: ArrestoColors.line),
                _settingRow(Icons.logout_rounded, 'Logout',
                    color: ArrestoColors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, String learnerId, String currentName) async {
    final controller = TextEditingController(text: currentName);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArrestoColors.surface,
        title:   Text('Edit Profile', style: ArrestoText.h4()),
        content: TextField(
          controller: controller,
          autofocus:  true,
          decoration: const InputDecoration(labelText: 'Display Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null || result.isEmpty || !context.mounted) return;

    try {
      await LearnerService.updateDisplayName(learnerId, result);
      ref.invalidate(profileProvider(learnerId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile.')),
        );
      }
    }
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        ArrestoColors.surface,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: ArrestoColors.cardBorder),
        ),
        child: Column(
          children: [
            Text(value, style: ArrestoText.h2()),
            Text(label, style: ArrestoText.small()),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(IconData icon, String label, {Color? color}) {
    final c = color ?? ArrestoColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: ArrestoText.body(color: c))),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: ArrestoColors.textMuted2),
        ],
      ),
    );
  }
}
