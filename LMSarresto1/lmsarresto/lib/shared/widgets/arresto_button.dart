import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

enum AButtonVariant { primary, ghost, dark, orange, danger }
enum AButtonSize { sm, md, lg }

class AButton extends StatelessWidget {
  const AButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AButtonVariant.primary,
    this.size = AButtonSize.md,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AButtonVariant variant;
  final AButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      AButtonVariant.primary => (AColors.amber, AColors.ink, Colors.transparent),
      AButtonVariant.ghost   => (Colors.transparent, AColors.ink, AColors.cardBorder),
      AButtonVariant.dark    => (AColors.ink, Colors.white, Colors.transparent),
      AButtonVariant.orange  => (AColors.orange, Colors.white, Colors.transparent),
      AButtonVariant.danger  => (AColors.redSoft, AColors.red, AColors.red.withValues(alpha: 0.3)),
    };
    final (vPad, hPad, fontSize) = switch (size) {
      AButtonSize.sm => (8.0, 14.0, 12.0),
      AButtonSize.md => (11.0, 18.0, 14.0),
      AButtonSize.lg => (14.0, 22.0, 15.0),
    };

    Widget content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null) ...[
          Icon(icon, size: fontSize + 2, color: fg),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: fg)),
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: TextButton(
        onPressed: (loading || onPressed == null) ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: border),
          ),
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
        ),
        child: content,
      ),
    );
  }
}
