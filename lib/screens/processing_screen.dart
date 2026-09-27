import 'package:flutter/material.dart';

import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'results_screen.dart';

/// Processing screen — hands the recorded sweep video to the C++ engine
/// (native/src/pipeline.cpp), which runs the entire sample -> blur filter
/// -> detect -> embed -> cluster -> match sequence natively in one call,
/// then navigates to [ResultsScreen] with the parsed JSON result.
class ProcessingScreen extends StatefulWidget {
  final String videoPath;
  final ClassroomEngine engine;

  const ProcessingScreen({
    super.key,
    required this.videoPath,
    required this.engine,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final results = await widget.engine.processSweepVideo(widget.videoPath);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultsScreen(initialResults: results)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkScaffoldBg : AppTheme.lightScaffoldBg,
      body: Stack(
        children: [
          // Background ambient glow
          Center(
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.discordPurple.withValues(alpha: isDark ? 0.20 : 0.12),
                ),
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _error != null
                  ? GlassCard(
                      padding: const EdgeInsets.all(24),
                      borderColor: AppTheme.discordRed.withValues(alpha: 0.3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.discordRed, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'Processing Failed',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: secondaryTextColor),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.discordPurple,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Go Back', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    )
                  : GlassCard(
                      hasGlow: true,
                      glowColor: AppTheme.discordPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 52,
                            height: 52,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.discordPurple),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Processing Sweep Video…',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Detecting faces, extracting features & clustering embeddings natively on-device',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

