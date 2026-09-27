import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Apple Face ID-Style Enrollment Screen with Radial Tick Ring
/// Interfaces seamlessly with C++ on-device engine (native/src/pipeline.cpp).
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

  Future<void> _captureAndEnroll() async {
    final controller = _controller;
    final rollNo = _rollNoController.text.trim();
    final name = _nameController.text.trim().isEmpty ? rollNo : _nameController.text.trim();

    if (controller == null || rollNo.isEmpty) {
      setState(() => _error = 'Please enter student Roll No / Name first.');
      return;
    }

    // Check duplicate student
    final isDuplicate = _enrolledStudents.any(
      (s) => (s['student_id'] as String? ?? '').trim().toLowerCase() == rollNo.toLowerCase(),
    );
    if (isDuplicate) {
      setState(() {
        _error = 'Student "$rollNo" is already enrolled. Please use a unique roll number.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
      _ticksCompleted = _totalTicks ~/ 2;
    });

    try {
      final photo = await controller.takePicture();
      final found = await widget.engine.enrollStudentFromPhoto(
        photoPath: photo.path,
        studentId: rollNo,
        name: name,
      );

      if (!found) {
        setState(() {
          _error = 'No face detected in the photo — try again with better lighting/framing.';
          _ticksCompleted = 0;
        });
        return;
      }

      setState(() => _ticksCompleted = _totalTicks);
      await _loadEnrolledStudents();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.discordGreen,
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('Enrolled $name ($rollNo) successfully!', style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      );
      _rollNoController.clear();
      _nameController.clear();
      setState(() => _ticksCompleted = 0);
    } catch (e) {
      setState(() {
        _error = 'Enrollment failed: $e';
        _ticksCompleted = 0;
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
                                subtitle: Text(
                                  'ID: $sId',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                    fontSize: 12,
                                  ),
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
                        'Student Enrollment',
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
                  const SizedBox(height: 16),

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
                  const SizedBox(height: 20),

                  // Error Banner
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
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
                  const SizedBox(height: 20),

                  // Capture & Enroll Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _captureAndEnroll,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.camera_enhance_rounded, color: Colors.white),
                      label: Text(
                        _isProcessing ? 'Extracting Face Biometrics…' : 'Capture & Enroll Face',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.discordPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: AppTheme.discordPurple.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
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
