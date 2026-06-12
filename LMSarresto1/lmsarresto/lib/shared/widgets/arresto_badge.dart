import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

enum ABadgeVariant { amber, green, red, blue, gray, orange }

class ABadge extends StatelessWidget {
  const ABadge(this.label, {super.key, this.variant = ABadgeVariant.gray, this.dot = false});

  final String label;
  final ABadgeVariant variant;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      ABadgeVariant.amber  => (AColors.amberSoft, AColors.orange),
      ABadgeVariant.green  => (AColors.greenSoft, AColors.green),
      ABadgeVariant.red    => (AColors.redSoft,   AColors.red),
      ABadgeVariant.blue   => (AColors.blueSoft,  AColors.blue),
      ABadgeVariant.orange => (AColors.orangeTint, AColors.orange),
      ABadgeVariant.gray   => (AColors.bg2,        AColors.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

ABadgeVariant statusVariant(String status) => switch (status.toLowerCase()) {
  'published'  => ABadgeVariant.green,
  'generating' => ABadgeVariant.amber,
  'draft'      => ABadgeVariant.gray,
  'review'     => ABadgeVariant.blue,
  'completed'  => ABadgeVariant.green,
  'processing' => ABadgeVariant.amber,
  'pending'    => ABadgeVariant.gray,
  'failed'     => ABadgeVariant.red,
  'active'     => ABadgeVariant.green,
  'inactive'   => ABadgeVariant.gray,
  'open'       => ABadgeVariant.orange,
  'resolved'   => ABadgeVariant.green,
  _            => ABadgeVariant.gray,
};
