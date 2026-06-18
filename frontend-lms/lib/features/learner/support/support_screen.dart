import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/arresto_card.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/arresto_ai_logo.dart';
import '../../../data/providers/app_state.dart';
import '../../shared/arresto_ai/arresto_ai_panel.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'Technical';
  bool _submitted = false;

  static const _categories = [
    'Technical',
    'Certificates',
    'Assessments',
    'Billing',
    'Other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.help_outline_rounded,
              title: 'Help & Support',
            ),
            const SizedBox(height: 20),
            isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _ContactForm()),
                      const SizedBox(width: 20),
                      Expanded(child: _SidePanel()),
                    ],
                  )
                : Column(
                    children: [
                      _ContactForm(),
                      const SizedBox(height: 16),
                      _SidePanel(),
                    ],
                  ),
            const SizedBox(height: 24),
            _MyTickets(tickets: tickets),
          ],
        ),
      );
  }
}

class _ContactForm extends StatefulWidget {
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return ArrestoCard(
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: ArrestoColors.green, size: 48),
            const SizedBox(height: 12),
            Text('Ticket Submitted!', style: ArrestoText.h3()),
            const SizedBox(height: 6),
            Text('We\'ll get back to you within 24 hours.',
                style: ArrestoText.body(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ArrestoButton(
              label: 'Submit Another',
              variant: ArrestoButtonVariant.ghost,
              onPressed: () => setState(() => _sent = false),
            ),
          ],
        ),
      );
    }

    return ArrestoCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact Admin', style: ArrestoText.h3()),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field('Full Name', hintText: 'James Harrington')),
                const SizedBox(width: 12),
                Expanded(child: _field('Email', hintText: 'james@example.com')),
              ],
            ),
            const SizedBox(height: 12),
            _field('Subject', hintText: 'Brief description of your issue'),
            const SizedBox(height: 12),
            _dropdown(),
            const SizedBox(height: 12),
            _field('Issue Description',
                maxLines: 5,
                hintText: 'Please describe your issue in detail...'),
            const SizedBox(height: 12),
            // Upload zone
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: ArrestoColors.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: ArrestoColors.lineStrong,
                    style: BorderStyle.solid),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.upload_file_rounded,
                        color: ArrestoColors.textMuted),
                    const SizedBox(width: 8),
                    Text('Drag & drop files or tap to upload',
                        style: ArrestoText.small()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ArrestoButton(
              label: 'Submit Ticket',
              fullWidth: true,
              size: ArrestoButtonSize.lg,
              icon: const Icon(Icons.send_rounded),
              onPressed: () => setState(() => _sent = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, {int maxLines = 1, String? hintText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ArrestoText.label()),
        const SizedBox(height: 5),
        TextFormField(
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }

  Widget _dropdown() {
    const cats = ['Technical', 'Certificates', 'Assessments', 'Billing', 'Other'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category', style: ArrestoText.label()),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: cats.first,
          decoration: const InputDecoration(),
          items: cats
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (_) {},
        ),
      ],
    );
  }
}

class _SidePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ArrestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FAQ', style: ArrestoText.h4()),
              const SizedBox(height: 12),
              ...[
                'How do I download my certificate?',
                'Why is my assessment locked?',
                'How do I reset my progress?',
                'Can I access courses offline?',
              ].map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right_rounded,
                            size: 16, color: ArrestoColors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(q,
                                style: ArrestoText.bodySm(
                                    color: ArrestoColors.blue))),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ArrestoColors.ink,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ArrestoAiLogo(size: 28),
                  const SizedBox(width: 8),
                  Text('Try Arresto AI first',
                      style: ArrestoText.bodyBold(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Get instant answers to your learning questions.',
                  style: ArrestoText.small(color: Colors.white60)),
              const SizedBox(height: 12),
              ArrestoButton(
                label: 'Ask AI',
                size: ArrestoButtonSize.sm,
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ArrestoAIPanel(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyTickets extends ConsumerWidget {
  final List tickets;
  const _MyTickets({required this.tickets});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tickets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Support Requests', style: ArrestoText.h3()),
        const SizedBox(height: 12),
        ...tickets.take(3).map((t) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: ArrestoColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ArrestoColors.cardBorder),
              ),
              child: Row(
                children: [
                  Text(t.id,
                      style: ArrestoText.mono()
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(t.subject,
                          style: ArrestoText.body(color: ArrestoColors.ink),
                          overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  StatusBadge(status: t.status),
                  const SizedBox(width: 8),
                  Text(t.date, style: ArrestoText.xs()),
                ],
              ),
            )),
      ],
    );
  }
}
