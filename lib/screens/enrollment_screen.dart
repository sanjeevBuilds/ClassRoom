import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Apple Face ID-Style 3D Multi-Pose Enrollment Screen with Radial Tick Ring
/// Captures 3 distinct angles per student (Frontal, Left 15°, Right 15°)
/// and stores all 3 512-D vectors in SQLite via the C++ engine.
class EnrollmentScreen extends StatefulWidget {
  final ClassroomEngine engine;

  const EnrollmentScreen({super.key, required this.engine});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> with SingleTickerProviderStateMixin {
  final _rollNoController = TextEditingController();
  final _nameController = TextEditingController();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isProcessing = false;
  String? _error;
  List<Map<String, dynamic>> _enrolledStudents = [];

  // Face ID Multi-Pose 3-Step State
  int _faceIdStep = 0; // 0 = Frontal (0°), 1 = Left (~15°), 2 = Right (~15°)
  final List<String> _capturedPhotos = [];

  // Face ID ring animation
  late AnimationController _ringAnimController;
  int _ticksCompleted = 0;
  final int _totalTicks = 48;

  @override
  void initState() {
    super.initState();
    _ringAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _initCamera();
    _loadEnrolledStudents();
  }

  Future<void> _loadEnrolledStudents() async {
    try {
      final list = await widget.engine.getEnrolledStudents();
      if (mounted) setState(() => _enrolledStudents = list);
    } catch (_) {}
  }

  Future<void> _initCamera([int? index]) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _error = 'No camera found on this device.');
      return;
    }
    _cameras = cameras;

    if (index != null && index >= 0 && index < _cameras.length) {
      _cameraIndex = index;
    } else {
      // Default to back camera for highest optical resolution
      final backIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = (backIdx != -1) ? backIdx : 0;
    }

    await _controller?.dispose();
    final selectedCamera = _cameras[_cameraIndex];
    final controller = CameraController(selectedCamera, ResolutionPreset.high, enableAudio: false);
    await controller.initialize();
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length <= 1) return;
    final nextIdx = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(nextIdx);
  }

  @override
  void dispose() {
    _ringAnimController.dispose();
    _controller?.dispose();
    _rollNoController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _resetPoseSequence() {
    setState(() {
      _faceIdStep = 0;
      _capturedPhotos.clear();
      _ticksCompleted = 0;
      _error = null;
    });
  }

  Future<void> _capturePoseStep() async {
    final controller = _controller;
    final rollNo = _rollNoController.text.trim();
    final name = _nameController.text.trim().isEmpty ? rollNo : _nameController.text.trim();

    if (controller == null || rollNo.isEmpty) {
      setState(() => _error = 'Please enter student Roll No (e.g. 23Z319) first.');
      return;
    }

    // Check duplicate student on first step
    if (_faceIdStep == 0) {
      final isDuplicate = _enrolledStudents.any(
        (s) => (s['student_id'] as String? ?? '').trim().toLowerCase() == rollNo.toLowerCase(),
      );
      if (isDuplicate) {
        setState(() {
          _error = 'Student "$rollNo" is already enrolled. Please use a unique roll number.';
        });
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final photo = await controller.takePicture();
      _capturedPhotos.add(photo.path);

      if (_faceIdStep == 0) {
        // Step 1 completed (Frontal) -> Move to Left Angle
        setState(() {
          _ticksCompleted = 16;
          _faceIdStep = 1;
        });
      } else if (_faceIdStep == 1) {
        // Step 2 completed (Left) -> Move to Right Angle
        setState(() {
          _ticksCompleted = 32;
          _faceIdStep = 2;
        });
      } else {
        // Step 3 completed (Right) -> Finalize all 3 poses in C++ engine
        setState(() => _ticksCompleted = 48);

        final enrolledCount = await widget.engine.enrollStudentFromPhotos(
          photoPaths: _capturedPhotos,
          studentId: rollNo,
          name: name,
        );

        if (enrolledCount == 0) {
          setState(() {
            _error = 'No face detected across the 3 photos. Please ensure good lighting and try again.';
            _resetPoseSequence();
          });
          return;
        }

        await _loadEnrolledStudents();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.discordGreen,
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Face ID Enrolled: $name ($rollNo) with $enrolledCount 3D Poses (Front, Left, Right)!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );

        _rollNoController.clear();
        _nameController.clear();
        _resetPoseSequence();
      }
    } catch (e) {
      setState(() {
        _error = 'Enrollment failed: $e';
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showEnrolledListModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return GlassCard(
              borderRadius: 28,
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Enrolled Students (${_enrolledStudents.length})',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_enrolledStudents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No students enrolled yet.',
                          style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: _enrolledStudents.length,
                          itemBuilder: (context, i) {
                            final s = _enrolledStudents[i];
                            final sName = s['name'] as String? ?? 'Unknown';
                            final sId = s['student_id'] as String? ?? '';
                            final embCount = s['embeddings_count'] as int? ?? 3;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.discordPurple.withValues(alpha: 0.18),
                                  child: Text(
                                    sName.isNotEmpty ? sName[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      color: AppTheme.discordPurple,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  sName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      'ID: $sId',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppTheme.discordGreen.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$embCount Poses',
                                        style: const TextStyle(
                                          color: AppTheme.discordGreen,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.discordRed),
                                  onPressed: () async {
                                    if (sId.isNotEmpty) {
                                      await widget.engine.deleteStudent(sId);
                                      await _loadEnrolledStudents();
                                      setModalState(() {});
                                      setState(() {});
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getStepInstruction() {
    switch (_faceIdStep) {
      case 0:
        return 'Step 1 of 3: Look straight at camera (Frontal 0°)';
      case 1:
        return 'Step 2 of 3: Turn head slightly LEFT (~15°)';
      case 2:
        return 'Step 3 of 3: Turn head slightly RIGHT (~15°)';
      default:
        return 'Center face in the circle';
    }
  }

  String _getButtonLabel() {
    if (_isProcessing) return 'Extracting 3D Landmarks…';
    switch (_faceIdStep) {
      case 0:
        return 'Capture Frontal Pose (1/3)';
      case 1:
        return 'Capture Left Angle (2/3)';
      case 2:
        return 'Capture Right Angle (3/3) & Finalize';
      default:
        return 'Capture Face';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBackCamera = _cameras.isNotEmpty &&
        _cameraIndex < _cameras.length &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkScaffoldBg : AppTheme.lightScaffoldBg,
      body: Stack(
        children: [
          // Background ambient lights
          Positioned(
            top: -80,
            right: -60,
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

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Bar / Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(4),
                        borderRadius: 14,
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Text(
                        '3D Face ID Enrollment',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      GlassCard(
                        padding: const EdgeInsets.all(4),
                        borderRadius: 14,
                        child: IconButton(
                          icon: const Icon(Icons.people_alt_outlined, size: 20, color: AppTheme.discordPurple),
                          tooltip: 'View Enrolled List',
                          onPressed: _showEnrolledListModal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Multi-Angle Step Indicator Chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildAngleBadge('1. Frontal', 0, _faceIdStep >= 1),
                      const SizedBox(width: 8),
                      _buildAngleBadge('2. Left 15°', 1, _faceIdStep >= 2),
                      const SizedBox(width: 8),
                      _buildAngleBadge('3. Right 15°', 2, _ticksCompleted == 48),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Camera Lens Indicator & Flip Toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.discordPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.discordPurple.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBackCamera ? Icons.camera_rear_rounded : Icons.camera_front_rounded,
                              size: 16,
                              color: AppTheme.discordPurple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isBackCamera ? 'BACK CAMERA (HD)' : 'FRONT CAMERA',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.discordPurple,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_cameras.length > 1) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.flip_camera_ios_rounded, color: AppTheme.discordPurple, size: 20),
                          tooltip: 'Switch Camera',
                          onPressed: _toggleCamera,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Dynamic Pose Guidance Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.discordPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.discordPurple.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _faceIdStep == 0
                              ? Icons.visibility_rounded
                              : (_faceIdStep == 1
                                  ? Icons.keyboard_double_arrow_left_rounded
                                  : Icons.keyboard_double_arrow_right_rounded),
                          size: 18,
                          color: AppTheme.discordPurple,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getStepInstruction(),
                          style: const TextStyle(
                            color: AppTheme.discordPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Apple Face ID Radial Aperture Viewfinder
                  Center(
                    child: SizedBox(
                      width: 250,
                      height: 250,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Animated Custom Face ID Radial Tick Ring
                          AnimatedBuilder(
                            animation: _ringAnimController,
                            builder: (context, child) {
                              return CustomPaint(
                                size: const Size(250, 250),
                                painter: _FaceIdRingPainter(
                                  ticksCompleted: _ticksCompleted,
                                  totalTicks: _totalTicks,
                                  isProcessing: _isProcessing,
                                  isDark: isDark,
                                  rotation: _ringAnimController.value * 2 * pi,
                                ),
                              );
                            },
                          ),

                          // Circular Camera Preview
                          ClipOval(
                            child: SizedBox(
                              width: 200,
                              height: 200,
                              child: _controller != null && _controller!.value.isInitialized
                                  ? AspectRatio(
                                      aspectRatio: _controller!.value.aspectRatio,
                                      child: CameraPreview(_controller!),
                                    )
                                  : Container(
                                      color: isDark ? Colors.black45 : Colors.grey.shade200,
                                      child: const Center(
                                        child: CircularProgressIndicator(color: AppTheme.discordPurple),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Error Banner
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.discordRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.discordRed.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.discordRed, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppTheme.discordRed, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Input Fields Card
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: 22,
                    child: Column(
                      children: [
                        TextField(
                          controller: _rollNoController,
                          enabled: _faceIdStep == 0,
                          style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                          decoration: InputDecoration(
                            labelText: 'Student Roll No (e.g. 23Z319)',
                            labelStyle: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(Icons.badge_rounded, color: AppTheme.discordPurple, size: 20),
                            filled: true,
                            fillColor: AppTheme.discordPurple.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppTheme.discordPurple.withValues(alpha: 0.2)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppTheme.discordPurple, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameController,
                          enabled: _faceIdStep == 0,
                          style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                          decoration: InputDecoration(
                            labelText: 'Student Full Name (Optional)',
                            labelStyle: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(Icons.person_rounded, color: AppTheme.discordPurple, size: 20),
                            filled: true,
                            fillColor: AppTheme.discordPurple.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppTheme.discordPurple.withValues(alpha: 0.2)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppTheme.discordPurple, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Capture Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _capturePoseStep,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              _faceIdStep == 2 ? Icons.check_circle_rounded : Icons.camera_enhance_rounded,
                              color: Colors.white,
                            ),
                      label: Text(
                        _getButtonLabel(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _faceIdStep == 2 ? AppTheme.discordGreen : AppTheme.discordPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: (_faceIdStep == 2 ? AppTheme.discordGreen : AppTheme.discordPurple)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ),

                  // Reset / Retake Button if in multi-step flow
                  if (_faceIdStep > 0) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _resetPoseSequence,
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.discordRed),
                      label: const Text('Reset & Start Over', style: TextStyle(color: AppTheme.discordRed, fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleBadge(String label, int stepIndex, bool isCompleted) {
    final isCurrent = _faceIdStep == stepIndex;
    final color = isCompleted
        ? AppTheme.discordGreen
        : (isCurrent ? AppTheme.discordPurple : Colors.grey.withValues(alpha: 0.5));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: isCurrent ? 1.5 : 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCompleted) ...[
            const Icon(Icons.check, size: 12, color: AppTheme.discordGreen),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the Apple Face ID radial tick ring
class _FaceIdRingPainter extends CustomPainter {
  final int ticksCompleted;
  final int totalTicks;
  final bool isProcessing;
  final bool isDark;
  final double rotation;

  _FaceIdRingPainter({
    required this.ticksCompleted,
    required this.totalTicks,
    required this.isProcessing,
    required this.isDark,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius - 14;

    for (int i = 0; i < totalTicks; i++) {
      final angle = (2 * pi / totalTicks) * i - (pi / 2);
      final isDone = i < ticksCompleted;

      final paint = Paint()
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;

      if (isDone) {
        paint.color = AppTheme.discordGreen;
      } else if (isProcessing) {
        final progressFactor = (i / totalTicks);
        paint.color = Color.lerp(
          AppTheme.discordPurple,
          AppTheme.discordGreen,
          (sin(rotation + progressFactor * 2 * pi) + 1) / 2,
        )!;
      } else {
        paint.color = isDark ? Colors.white24 : Colors.black12;
      }

      final p1 = Offset(
        center.dx + innerRadius * cos(angle),
        center.dy + innerRadius * sin(angle),
      );
      final p2 = Offset(
        center.dx + outerRadius * cos(angle),
        center.dy + outerRadius * sin(angle),
      );

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceIdRingPainter oldDelegate) {
    return oldDelegate.ticksCompleted != ticksCompleted ||
        oldDelegate.isProcessing != isProcessing ||
        oldDelegate.rotation != rotation;
  }
}
