import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class AProgressBar extends StatelessWidget {
  const AProgressBar({
    super.key,
    required this.value,
    this.height = 8.0,
    this.color = AColors.amber,
    this.trackColor = AColors.bg2,
    this.radius = 4.0,
  });

  final double value; // 0.0 to 1.0
  final double height;
  final Color color;
  final Color trackColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: trackColor,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class AProgressBarLabeled extends StatelessWidget {
  const AProgressBarLabeled({
    super.key,
    required this.value,
    this.height = 8.0,
    this.color = AColors.amber,
    this.showPercent = true,
    this.label,
  });

  final double value;
  final double height;
  final Color color;
  final bool showPercent;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? (showPercent ? '${(value * 100).round()}%' : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (displayLabel != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(displayLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
      AProgressBar(value: value, height: height, color: color),
    ]);
  }
}
