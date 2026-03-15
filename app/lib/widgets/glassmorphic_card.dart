import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Clean card — white × soft purple theme.
class GlassmorphicCard extends StatelessWidget {
  const GlassmorphicCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blur = 0, // kept for signature compat, unused
    this.opacity = 1.0, // kept for signature compat
    this.borderOpacity = 1.0,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final double borderOpacity;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? ArqivonTheme.darkCard : ArqivonTheme.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFDCE5F0),
        ),
        boxShadow: isDark
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x08C98B4E),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
