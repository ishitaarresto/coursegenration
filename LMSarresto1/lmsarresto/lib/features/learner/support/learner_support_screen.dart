import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_button.dart';

class LearnerSupportScreen extends StatefulWidget {
  const LearnerSupportScreen({super.key});
  @override
  State<LearnerSupportScreen> createState() => _LearnerSupportScreenState();
}

class _LearnerSupportScreenState extends State<LearnerSupportScreen> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Support', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Get help with your learning experience', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 28),

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Contact form
          Expanded(
            flex: 2,
            child: APanel(
              title: 'Submit a Request',
              subtitle: 'Our team typically responds within 24 hours',
              child: _submitted
                  ? _SuccessView(onReset: () => setState(() {
                      _submitted = false;
                      _subjectCtrl.clear();
                      _bodyCtrl.clear();
                    }))
                  : _ContactForm(
                      subjectCtrl: _subjectCtrl,
                      bodyCtrl: _bodyCtrl,
                      onSubmit: () => setState(() => _submitted = true),
                    ),
            ),
          ),
          const SizedBox(width: 24),

          // Quick links
          SizedBox(
            width: 260,
            child: Column(children: [
              APanel(
                title: 'Common Topics',
                child: Column(children: const [
                  _TopicTile(icon: Icons.play_circle_outline, label: 'Video not playing'),
                  _TopicTile(icon: Icons.workspace_premium_outlined, label: 'Certificate issue'),
                  _TopicTile(icon: Icons.lock_outline_rounded, label: 'Account access'),
                  _TopicTile(icon: Icons.quiz_outlined, label: 'Assessment problem'),
                  _TopicTile(icon: Icons.translate_rounded, label: 'Language settings'),
                ]),
              ),
              const SizedBox(height: 16),
              APanel(
                title: 'Arresto AI',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Get instant answers from our AI assistant.',
                      style: TextStyle(fontSize: 13, color: AColors.textMuted)),
                  const SizedBox(height: 12),
                  AButton(
                    label: 'Chat with AI',
                    icon: Icons.smart_toy_outlined,
                    fullWidth: true,
                    size: AButtonSize.sm,
                    onPressed: () {},
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _ContactForm extends StatelessWidget {
  const _ContactForm({required this.subjectCtrl, required this.bodyCtrl, required this.onSubmit});
  final TextEditingController subjectCtrl;
  final TextEditingController bodyCtrl;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: subjectCtrl,
        decoration: const InputDecoration(
          labelText: 'Subject',
          hintText: 'Brief description of your issue',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: bodyCtrl,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: 'Message',
          hintText: 'Describe the issue in detail…',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        AButton(label: 'Send Request', icon: Icons.send_rounded, onPressed: onSubmit),
      ]),
    ]);
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 60, height: 60,
          decoration: const BoxDecoration(color: AColors.greenSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: AColors.green, size: 32),
        ),
        const SizedBox(height: 16),
        const Text('Request Submitted!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AColors.ink)),
        const SizedBox(height: 8),
        const Text('We\'ll get back to you within 24 hours.',
            style: TextStyle(fontSize: 13, color: AColors.textMuted), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        AButton(label: 'Submit Another', variant: AButtonVariant.ghost, onPressed: onReset),
      ]),
    ),
  );
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () {},
      child: Row(children: [
        Icon(icon, size: 16, color: AColors.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AColors.textSecond))),
        const Icon(Icons.chevron_right_rounded, size: 16, color: AColors.textMuted),
      ]),
    ),
  );
}
