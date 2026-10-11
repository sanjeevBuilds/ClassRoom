import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable full-bleed ambient background with silky smooth radial mesh glow
/// layers and deep dark/light adaptive gradients.
class AmbientBackground extends StatelessWidget {
  final Widget child;

  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Base Adaptive Gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF131417), // Deep midnight
                      Color(0xFF1E1F24), // Discord slate dark
                      Color(0xFF17181C), // Deep charcoal
                    ]
                  : const [
                      Color(0xFFF4F6F9), // Soft crisp modern light
                      Color(0xFFFFFFFF), // Pure white center
                      Color(0xFFECEFF4), // Subtle cool tint
                    ],
            ),
          ),
        ),

        // 2. Top-Left Ambient Blurple Orb
        Positioned(
          top: -80,
          left: -60,
          child: IgnorePointer(
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.discordPurple.withValues(alpha: isDark ? 0.28 : 0.16),
                    AppTheme.discordPurple.withValues(alpha: isDark ? 0.10 : 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 3. Middle-Right Soft Accent Orb
        Positioned(
          top: 240,
          right: -80,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.discordLightPurple.withValues(alpha: isDark ? 0.20 : 0.12),
                    AppTheme.discordFuchsia.withValues(alpha: isDark ? 0.08 : 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 4. Bottom-Left Warm Glow Orb
        Positioned(
          bottom: -70,
          left: -40,
          child: IgnorePointer(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.discordDeepPurple.withValues(alpha: isDark ? 0.22 : 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.8],
                ),
              ),
            ),
          ),
        ),

        // 5. Content Foreground
        child,
      ],
    );
  }
}
