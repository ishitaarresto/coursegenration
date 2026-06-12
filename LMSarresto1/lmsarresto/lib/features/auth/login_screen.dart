import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/providers/auth_provider.dart';
import '../../shared/widgets/arresto_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nameCtrl  = TextEditingController(text: 'Ariba');
  final _emailCtrl = TextEditingController(text: 'ariba@arresto.in');
  String _role = 'admin';
  bool _loading = false;

  Future<void> _login() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    await ref.read(authProvider.notifier).login(name, email, _role);
    if (mounted) context.go(_role == 'admin' ? '/admin' : '/learner');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AColors.bg,
      body: CustomPaint(
        painter: _BgPainter(),
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Logo
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: AColors.ink, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AColors.amber, borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text('A', style: TextStyle(
                    color: AColors.ink, fontWeight: FontWeight.w800, fontSize: 22))),
              )),
            ),
            const SizedBox(height: 20),
            Text('Arresto LMS', style: AText.h1()),
            const SizedBox(height: 6),
            Text('YOUR SAFETY TRAINING PLATFORM',
                style: AText.eyebrow(color: AColors.textMuted)),
            const SizedBox(height: 40),
            // Login card
            Container(
              width: 440,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AColors.cardBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 32, offset: const Offset(0, 8))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sign in', style: AText.h2()),
                const SizedBox(height: 4),
                Text('Continue to Arresto LMS', style: AText.body()),
                const SizedBox(height: 28),

                Text('Full Name', style: AText.label()),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(hintText: 'Your name'),
                ),
                const SizedBox(height: 16),

                Text('Email', style: AText.label()),
                const SizedBox(height: 6),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(hintText: 'you@arresto.in'),
                ),
                const SizedBox(height: 16),

                Text('Sign in as', style: AText.label()),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _RoleCard(
                    label: 'Admin',
                    subtitle: 'Manage courses & learners',
                    icon: Icons.admin_panel_settings_rounded,
                    selected: _role == 'admin',
                    onTap: () => setState(() => _role = 'admin'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _RoleCard(
                    label: 'Learner',
                    subtitle: 'Browse & take courses',
                    icon: Icons.school_rounded,
                    selected: _role == 'learner',
                    onTap: () => setState(() => _role = 'learner'),
                  )),
                ]),
                const SizedBox(height: 24),
                AButton(
                  label: 'Sign in',
                  onPressed: _login,
                  loading: _loading,
                  fullWidth: true,
                  size: AButtonSize.lg,
                ),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
  }
}

// Subtle ambient blobs — no package needed
class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    p.color = AColors.amber.withValues(alpha: 0.07);
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.05), 200, p);
    p.color = AColors.amber.withValues(alpha: 0.05);
    canvas.drawCircle(Offset(size.width * 0.06, size.height * 0.92), 160, p);
    p.color = AColors.ink.withValues(alpha: 0.03);
    canvas.drawCircle(Offset(size.width * 0.10, size.height * 0.12), 90, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.label, required this.subtitle, required this.icon,
      required this.selected, required this.onTap});
  final String label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AColors.amberSoft : AColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AColors.amber : AColors.cardBorder, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 26, color: selected ? AColors.orange : AColors.textMuted),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: selected ? AColors.ink : AColors.textSecond)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AColors.textMuted),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
