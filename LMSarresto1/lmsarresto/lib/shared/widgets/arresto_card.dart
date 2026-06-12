import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class ACard extends StatelessWidget {
  const ACard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 16.0,
    this.border = true,
    this.shadow = true,
    this.color = AColors.surface,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool border;
  final bool shadow;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: AColors.cardBorder) : null,
        boxShadow: shadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 4))]
            : null,
      ),
      child: child,
    );
    if (onTap != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.black.withValues(alpha: 0.025),
            splashColor: Colors.black.withValues(alpha: 0.04),
            child: box,
          ),
        ),
      );
    }
    return box;
  }
}

class APanel extends StatelessWidget {
  const APanel({super.key, required this.title, required this.child, this.action, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ACard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.ink)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: const TextStyle(fontSize: 12, color: AColors.textMuted)),
              ],
            ]),
          ),
          if (action != null) action!,
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}
