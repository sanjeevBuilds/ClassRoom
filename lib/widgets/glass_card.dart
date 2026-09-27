import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable Glassmorphism container with backdrop blur, frosted linear gradients,
/// subtle translucent borders, and soft Discord Purple ambient glow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final bool hasGlow;
  final Color? glowColor;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 16,
    this.borderRadius = 22,
    this.padding,
    this.margin,
    this.borderColor,
    this.borderWidth = 1.2,
    this.onTap,
    this.hasGlow = false,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : AppTheme.discordPurple.withValues(alpha: 0.18);

    final bgColors = isDark
        ? [
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.03),
          ]
        : [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.65),
          ];

    final effectiveGlow = glowColor ?? AppTheme.discordPurple;

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          if (hasGlow)
            BoxShadow(
              color: effectiveGlow.withValues(alpha: isDark ? 0.28 : 0.16),
              blurRadius: 24,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            )
          else
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : AppTheme.discordPurple.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bgColors,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? defaultBorderColor,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: content,
        ),
      );
    }
    return content;
  }
}

/// Extension on Widget to easily apply a Gaussian blur effect
extension BlurExtension on Widget {
  Widget blurred({double blur = 40.0}) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: this,
    );
  }
}

