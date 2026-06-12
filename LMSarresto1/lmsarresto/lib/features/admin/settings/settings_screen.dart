import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/colors.dart';
import '../../../core/api/document_service.dart';
import '../../../core/providers/library_provider.dart';
import '../../../shared/widgets/arresto_card.dart';
import '../../../shared/widgets/arresto_button.dart';
import '../../../shared/widgets/arresto_badge.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _section = 0;
  bool _uploading = false;
  String _uploadMsg = '';

  Future<void> _uploadDoc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() { _uploading = true; _uploadMsg = 'Uploading ${file.name}…'; });
    try {
      final res = await DocumentService.uploadDocument(file.bytes!, file.name);
      if (mounted) {
        ref.read(documentsProvider.notifier).refresh();
        setState(() { _uploadMsg = 'Uploaded! ${res['chunks_created'] ?? 0} chunks created.'; });
      }
    } catch (e) {
      if (mounted) setState(() => _uploadMsg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static const _sections = [
    'Documents', 'AI Generation', 'Platform', 'Branding',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AColors.ink)),
        const Text('Configure your LMS platform', style: TextStyle(fontSize: 14, color: AColors.textMuted)),
        const SizedBox(height: 28),

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Sidebar nav
          SizedBox(
            width: 200,
            child: ACard(
              padding: const EdgeInsets.all(8),
              child: Column(children: _sections.asMap().entries.map((e) => _SettingsNavItem(
                label: e.value,
                active: _section == e.key,
                onTap: () => setState(() => _section = e.key),
              )).toList()),
            ),
          ),
          const SizedBox(width: 24),

          // Content
          Expanded(child: _sectionContent()),
        ]),
      ]),
    );
  }

  Widget _sectionContent() {
    return switch (_section) {
      0 => _DocumentsSection(uploading: _uploading, uploadMsg: _uploadMsg, onUpload: _uploadDoc),
      _ => APanel(title: _sections[_section], child: const Text(
          'This section will be available in a future update.',
          style: TextStyle(fontSize: 13, color: AColors.textMuted))),
    };
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: active ? AColors.bg2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: active ? AColors.ink : AColors.textMuted)),
      ),
    );
  }
}

class _DocumentsSection extends ConsumerWidget {
  const _DocumentsSection({required this.uploading, required this.uploadMsg, required this.onUpload});
  final bool uploading;
  final String uploadMsg;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider);

    return APanel(
      title: 'Knowledge Base Documents',
      subtitle: 'Upload PDFs, DOCX, or PPTX files to use as course sources',
      action: AButton(
        label: 'Upload Document',
        icon: Icons.upload_rounded,
        size: AButtonSize.sm,
        onPressed: uploading ? null : onUpload,
        loading: uploading,
      ),
      child: Column(children: [
        if (uploadMsg.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: uploadMsg.startsWith('Error') ? AColors.redSoft : AColors.greenSoft,
              borderRadius: BorderRadius.circular(8)),
            child: Text(uploadMsg, style: TextStyle(
                fontSize: 13,
                color: uploadMsg.startsWith('Error') ? AColors.red : AColors.green)),
          ),
        docsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e', style: const TextStyle(color: AColors.red)),
          data: (docs) => docs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No documents uploaded yet.',
                      style: TextStyle(color: AColors.textMuted)),
                )
              : Column(children: docs.map((doc) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    ABadge(doc.ext, variant: ABadgeVariant.blue),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(doc.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.ink),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${doc.chunkCount} chunks', style: const TextStyle(fontSize: 11, color: AColors.textMuted)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AColors.textMuted),
                      onPressed: () async {
                        await DocumentService.deleteDocument(doc.sourceFile);
                        ref.read(documentsProvider.notifier).refresh();
                      },
                    ),
                  ]),
                )).toList()),
        ),
      ]),
    );
  }
}
