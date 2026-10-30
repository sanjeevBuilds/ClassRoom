import 'dart:math';
import 'package:flutter/material.dart';

import '../models/attendance_result.dart';
import '../models/attendance_session.dart';
import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/ambient_background.dart';
import 'results_screen.dart';

/// Processing screen — runs single or multiple classroom sweep videos through
/// the native C++ engine (native/src/pipeline.cpp) on background isolates,
/// aggregates multi-angle detections into a consolidated roster, and navigates
/// to [ResultsScreen].
class ProcessingScreen extends StatefulWidget {
  final List<String> videoPaths;
  final ClassroomEngine engine;
  final List<AttendanceResult>? initialExistingResults;
  final String? checkpointLabel;

  /// Single video sweep constructor
  ProcessingScreen({
    super.key,
    required String videoPath,
    required this.engine,
    this.initialExistingResults,
    this.checkpointLabel,
  }) : videoPaths = [videoPath];

  /// Multi-sweep video constructor
  const ProcessingScreen.multi({
    super.key,
    required this.videoPaths,
    required this.engine,
    this.initialExistingResults,
    this.checkpointLabel,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String? _error;
  int _currentSweep = 1;
  int _totalSweeps = 1;
  String _statusMessage = 'Initializing on-device vision pipeline…';

  @override
  void initState() {
    super.initState();
    _totalSweeps = widget.videoPaths.length;
    _run();
  }

  Future<void> _run() async {
    try {
      final results = await widget.engine.processMultipleSweeps(
        widget.videoPaths,
        onProgress: (current, total, msg) {
          if (mounted) {
            setState(() {
              _currentSweep = current;
              _totalSweeps = total;
              _statusMessage = msg;
            });
          }
        },
      );

      // Record this sweep into the persistent classroom session
      final session = await widget.engine.recordSessionSweep(
        classId: widget.engine.currentClassId,
        sweepResults: results,
        checkpointLabel: widget.checkpointLabel,
        videoPaths: widget.videoPaths,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            session: session,
            initialResults: session.consolidatedResults,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    // Relative responsive card width bounded between 280px and 520px
    final double cardWidth = min(size.width * 0.90, 520.0);
    final double verticalPadding = (size.height * 0.035).clamp(16.0, 36.0);
    final double horizontalPadding = (size.width * 0.05).clamp(16.0, 32.0);

    final bool isMulti = widget.videoPaths.length > 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: (size.width * 0.05).clamp(12.0, 24.0),
                vertical: 16.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: _error != null
                    ? GlassCard(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: verticalPadding,
                        ),
                        borderColor: AppTheme.discordRed.withValues(alpha: 0.35),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.discordRed, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'Processing Failed',
                              style: TextStyle(
                                fontSize: (size.width * 0.045).clamp(16.0, 20.0),
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '$_error',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: (size.width * 0.032).clamp(12.0, 14.0),
                                color: secondaryTextColor,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.discordPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.arrow_back_rounded, size: 18),
                              onPressed: () => Navigator.pop(context),
                              label: const Text('Go Back', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      )
                    : GlassCard(
                        hasGlow: true,
                        glowColor: AppTheme.discordPurple,
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: verticalPadding,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Multi-Sweep Badge
                            if (isMulti)
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.discordPurple.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.discordPurple.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, size: 15, color: AppTheme.discordPurple),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Multi-Sweep Session • $_totalSweeps Angles',
                                      style: const TextStyle(
                                        color: AppTheme.discordPurple,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Progress Indicator
                            SizedBox(
                              width: (size.width * 0.14).clamp(52.0, 68.0),
                              height: (size.width * 0.14).clamp(52.0, 68.0),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    strokeWidth: 3.8,
                                    value: isMulti && _totalSweeps > 0
                                        ? (_currentSweep / _totalSweeps)
                                        : null,
                                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.discordPurple),
                                  ),
                                  if (isMulti)
                                    Text(
                                      '$_currentSweep/$_totalSweeps',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Dynamic Title
                            Text(
                              isMulti
                                  ? 'Aggregating Sweep $_currentSweep of $_totalSweeps…'
                                  : 'Processing Sweep Video…',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: (size.width * 0.042).clamp(16.0, 19.0),
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Dynamic Status Message
                            Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: (size.width * 0.031).clamp(12.0, 14.0),
                                color: secondaryTextColor,
                                height: 1.4,
                              ),
                            ),

                            // Multi-Sweep Progress Steps (Relative flex pills)
                            if (isMulti) ...[
                              const SizedBox(height: 22),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(_totalSweeps, (index) {
                                  final stepNum = index + 1;
                                  final isCompleted = stepNum < _currentSweep;
                                  final isCurrent = stepNum == _currentSweep;

                                  final Color bgColor;
                                  final Color borderColor;
                                  final Color textColor;

                                  if (isCompleted) {
                                    bgColor = AppTheme.discordGreen.withValues(alpha: 0.18);
                                    borderColor = AppTheme.discordGreen.withValues(alpha: 0.45);
                                    textColor = AppTheme.discordGreen;
                                  } else if (isCurrent) {
                                    bgColor = AppTheme.discordPurple.withValues(alpha: 0.22);
                                    borderColor = AppTheme.discordPurple;
                                    textColor = AppTheme.discordPurple;
                                  } else {
                                    bgColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04);
                                    borderColor = isDark ? Colors.white12 : Colors.black12;
                                    textColor = secondaryTextColor;
                                  }

                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isCompleted)
                                          const Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.discordGreen)
                                        else if (isCurrent)
                                          const SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.0,
                                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.discordPurple),
                                            ),
                                          )
                                        else
                                          Icon(Icons.circle_outlined, size: 11, color: textColor),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Sweep $stepNum',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ],

                            const SizedBox(height: 16),
                            Text(
                              'Running YuNet INT8 & ArcFace 512-D on-device • 100% offline',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: secondaryTextColor.withValues(alpha: 0.7),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
