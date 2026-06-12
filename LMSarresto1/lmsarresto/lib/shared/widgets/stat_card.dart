import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.barColor = AColors.amber,
    this.sub,
    this.delta,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color barColor;
  final String? sub;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coloured top accent strip
            Container(height: 4, color: barColor),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(label, style: AText.small()),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: barColor.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 20, color: barColor),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(value, style: AText.stat()),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, style: AText.small()),
                  ],
                  if (delta != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      delta!,
                      style: AText.smallBold(
                        color: delta!.startsWith('+') ? AColors.green : AColors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
