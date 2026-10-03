import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/detection.dart';
import '../modules/pose_estimation/face_pose.dart';
import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Enrollment screen — adds a student to the local roster from a captured
/// photo. MVP simplification: one reference photo per student, taken here
/// (the real plan is multiple photos across angles/lighting).
///
/// Owner: Teammate 5 (Module 5)
class EnrollmentScreen extends StatefulWidget {
  final ClassroomEngine engine;

  const EnrollmentScreen({super.key, required this.engine});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _nameController = TextEditingController();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isProcessing = false;
  String? _error;
  List<Map<String, dynamic>> _enrolledStudents = [];
  FacePose? _lastPose;

  // Face ID Multi-Pose Enrollment State
  bool _isFaceIdMode = true; // Default to authentic Face ID multi-pose
  int _faceIdStep = 0; // 0 = Frontal, 1 = Left, 2 = Right
  final List<Float32List> _faceIdEmbeddings = [];
  final List<FacePose> _faceIdPoses = [];

  @override
  void initState() {
    super.initState();
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
      // Default to BACK camera for high-resolution 6-axis pose modeling
      final backIdx = _cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = (backIdx != -1) ? backIdx : 0;
    }

    await _controller?.dispose();
    final selectedCamera = _cameras[_cameraIndex];
    final controller = CameraController(selectedCamera, ResolutionPreset.high,
        enableAudio: false);
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
    _controller?.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _captureAndEnroll() async {
    final controller = _controller;
    final name = _nameController.text.trim();
    if (controller == null || name.isEmpty) {
      setState(() => _error = 'Please enter student roll no / name first.');
      return;
    }

    // Restrict duplicate names (case-insensitive)
    final isDuplicate = _enrolledStudents.any(
      (s) =>
          (s['name'] as String? ?? '').trim().toLowerCase() ==
          name.toLowerCase(),
    );
    if (isDuplicate) {
      setState(() {
        _error =
            'Student "$name" is already enrolled. Please use a unique name.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final photo = await controller.takePicture();
      final found = await widget.engine.enrollStudentFromPhoto(
        photoPath: photo.path,
        studentId: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
      );

      if (!found) {
        setState(() {
          _error =
              'No face detected in the photo — try again with better lighting/framing.';
        });
        return;
      }

      _lastPose = widget.engine.lastEnrollmentPose;
      await _loadEnrolledStudents();
      if (!mounted) return;

      final poseText = _lastPose != null
          ? ' | Pose: Yaw ${_lastPose!.yaw.toStringAsFixed(0)}°, Pitch ${_lastPose!.pitch.toStringAsFixed(0)}°, Frontality: ${(_lastPose!.frontalityScore * 100).toStringAsFixed(0)}%'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enrolled $name$poseText'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      _nameController.clear();
    } catch (e) {
      setState(() => _error = 'Enrollment failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _captureFaceIdPose() async {
    final controller = _controller;
    final name = _nameController.text.trim();
    if (controller == null || name.isEmpty) {
      setState(() => _error = 'Please enter student roll no / name first.');
      return;
    }

    if (_faceIdStep == 0) {
      final isDuplicate = _enrolledStudents.any(
        (s) =>
            (s['name'] as String? ?? '').trim().toLowerCase() ==
            name.toLowerCase(),
      );
      if (isDuplicate) {
        setState(() => _error = 'Student "$name" is already enrolled.');
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final photo = await controller.takePicture();
      final embedding = await widget.engine.processFacePhoto(photo.path);

      if (embedding == null) {
        setState(() {
          _error =
              'No face detected! Center face in the Face ID ring and try again.';
        });
        return;
      }

      final pose = widget.engine.lastEnrollmentPose ??
          const FacePoseEstimator().estimatePose(
            Detection(
                frameId: 0,
                timestampSec: 0,
                bbox: [0, 0, 100, 100],
                confidence: 0.9,
                detector: 'yunet',
                detIndex: 0),
          );

      _faceIdEmbeddings.add(embedding.vector);
      _faceIdPoses.add(pose);
      _lastPose = pose;

      if (_faceIdStep < 2) {
        setState(() {
          _faceIdStep++;
        });
      } else {
        // All 3 angles completed: finalize multi-pose roster enrollment
        final studentId = DateTime.now().millisecondsSinceEpoch.toString();
        await widget.engine.enrollStudentWithEmbeddings(
          studentId: studentId,
          name: name,
          embeddings: _faceIdEmbeddings,
        );

        await _loadEnrolledStudents();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Face ID Enrolled: $name with 3 3D Poses (Front, Left, Right)!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0F172A),
            duration: const Duration(seconds: 4),
          ),
        );

        setState(() {
          _faceIdStep = 0;
          _faceIdEmbeddings.clear();
          _faceIdPoses.clear();
          _nameController.clear();
        });
      }
    } catch (e) {
      setState(() => _error = 'Face ID capture failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetFaceId() {
    widget.engine.resetPendingFaceId();
    setState(() {
      _faceIdStep = 0;
      _faceIdEmbeddings.clear();
      _faceIdPoses.clear();
      _error = null;
    });
  }

  Future<void> _deleteIndividualStudent(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text('Delete $name and their face data from the roster?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.engine.deleteStudent(studentId);
      await _loadEnrolledStudents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $name from roster.')),
        );
      }
    }
  }

  Future<void> _exportRoster() async {
    if (_enrolledStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No students to export! Enroll students first.')),
      );
      return;
    }
    try {
      final file = await widget.engine.exportClassroomRoster();
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Classroom Roster Export: ${widget.engine.currentClassId} (${_enrolledStudents.length} Students with 512-d Face Embeddings)',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Exported ${_enrolledStudents.length} students from ${widget.engine.currentClassId}!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _showImportDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Classroom Roster'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the exported classroom JSON package below to import all students and face embeddings:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '{"class_id": "CS101", "students": [...]}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.file_download_done_rounded),
            label: const Text('Import'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (result == true && textController.text.trim().isNotEmpty) {
      try {
        final count = await widget.engine
            .importClassroomRoster(textController.text.trim());
        await _loadEnrolledStudents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Successfully imported $count students into ${widget.engine.currentClassId}!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Import failed: Invalid roster format ($e)')),
          );
        }
      }
    }
  }

  void _showEnrolledListModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                height: MediaQuery.of(context).size.height * 0.70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
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
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_enrolledStudents.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'No students enrolled yet.',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: _enrolledStudents.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = _enrolledStudents[i];
                            final id = s['student_id'] as String? ?? '';
                            final sName = s['name'] as String? ?? 'Unknown';
                            return GlassCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              borderRadius: 16,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppTheme.discordPurple.withValues(alpha: 0.18),
                                    child: Text(
                                      sName.isNotEmpty ? sName[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        color: AppTheme.discordPurple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: $id',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppTheme.discordRed,
                                      size: 20,
                                    ),
                                    tooltip: 'Delete $sName',
                                    onPressed: () async {
                                      await _deleteIndividualStudent(id, sName);
                                      setModalState(() {});
                                    },
                                  ),
                                ],
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

  Future<void> _confirmClearRoster() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Enrolled Faces?'),
        content: const Text(
            'This will delete all previously enrolled student records so you can start completely fresh.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.engine.clearRoster();
      await _loadEnrolledStudents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('All enrolled faces cleared. Roster is fresh!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Enroll Student',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          Badge(
            label: Text('${_enrolledStudents.length}'),
            isLabelVisible: _enrolledStudents.isNotEmpty,
            child: IconButton(
              icon: const Icon(Icons.people_alt_rounded),
              tooltip: 'View Enrolled Students',
              onPressed: _showEnrolledListModal,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Roster Options',
            onSelected: (action) {
              if (action == 'export') {
                _exportRoster();
              } else if (action == 'import') {
                _showImportDialog();
              } else if (action == 'clear') {
                _confirmClearRoster();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.ios_share_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Export Roster (JSON)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_download_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Import Roster'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded,
                        size: 20, color: Colors.redAccent),
                    SizedBox(width: 12),
                    Text('Clear All Faces',
                        style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Builder(
            builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Column(
                children: [
                  // Student Name Input in GlassCard
                  GlassCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    borderRadius: 18,
                    child: TextField(
                      controller: _nameController,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Student Roll No (e.g. 23Z...)',
                        hintStyle: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                                  .withValues(alpha: 0.6)
                              : AppTheme.lightTextSecondary
                                  .withValues(alpha: 0.6),
                          fontSize: 15,
                        ),
                        prefixIcon: const Icon(Icons.badge_rounded,
                            color: AppTheme.discordPurple),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Mode Toggle: Face ID (Apple-Style) vs Quick 1-Shot
                  GlassCard(
                    padding: const EdgeInsets.all(4),
                    borderRadius: 14,
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isFaceIdMode = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _isFaceIdMode
                                    ? AppTheme.discordPurple
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: _isFaceIdMode
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.discordPurple
                                              .withOpacity(0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.face_retouching_natural_rounded,
                                      size: 16,
                                      color: _isFaceIdMode
                                          ? Colors.white
                                          : (isDark
                                              ? Colors.white60
                                              : Colors.black54),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '3D Face ID',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _isFaceIdMode
                                            ? Colors.white
                                            : (isDark
                                                ? Colors.white70
                                                : Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isFaceIdMode = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_isFaceIdMode
                                    ? AppTheme.discordPurple
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !_isFaceIdMode
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.discordPurple
                                              .withOpacity(0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_rounded,
                                      size: 16,
                                      color: !_isFaceIdMode
                                          ? Colors.white
                                          : (isDark
                                              ? Colors.white60
                                              : Colors.black54),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Quick 1-Shot',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: !_isFaceIdMode
                                            ? Colors.white
                                            : (isDark
                                                ? Colors.white70
                                                : Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Camera Viewfinder (Face ID Circular Ring vs Standard Preview)
                  _isFaceIdMode
                      ? _buildFaceIdViewfinder()
                      : SizedBox(
                          height: 320,
                          child: _buildStandardCameraPreview(),
                        ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.discordRed.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.discordRed.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppTheme.discordRed, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: AppTheme.discordRed, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Action Buttons
                  if (_isFaceIdMode)
                    Column(
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _faceIdStep == 2
                                ? AppTheme.discordGreen
                                : AppTheme.discordPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 6,
                            shadowColor: (_faceIdStep == 2
                                    ? AppTheme.discordGreen
                                    : AppTheme.discordPurple)
                                .withOpacity(0.4),
                          ),
                          onPressed: _isProcessing ? null : _captureFaceIdPose,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Icon(_faceIdStep == 0
                                  ? Icons.filter_center_focus_rounded
                                  : (_faceIdStep == 1
                                      ? Icons.arrow_back_rounded
                                      : Icons.arrow_forward_rounded)),
                          label: Text(
                            _isProcessing
                                ? 'Processing Angle…'
                                : (_faceIdStep == 0
                                    ? 'Capture Pose 1: Frontal'
                                    : (_faceIdStep == 1
                                        ? 'Capture Pose 2: Turn Left'
                                        : 'Capture Pose 3: Turn Right & Finish')),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_faceIdStep > 0)
                          TextButton.icon(
                            onPressed: _isProcessing ? null : _resetFaceId,
                            icon: const Icon(Icons.restart_alt_rounded,
                                size: 16, color: AppTheme.discordPurple),
                            label: const Text('Restart Face ID Scan',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.discordPurple)),
                          ),
                      ],
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.discordPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 6,
                        shadowColor: AppTheme.discordPurple.withOpacity(0.4),
                      ),
                      onPressed: _isProcessing ? null : _captureAndEnroll,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(
                          _isProcessing ? 'Processing…' : 'Capture & Enroll'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFaceIdViewfinder() {
    final controller = _controller;
    if (_error != null && controller == null) {
      return Center(child: Text(_error!));
    }
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Starting camera...',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final isBack = _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    final stepPrompts = [
      'Look straight into the circle',
      'Turn your head slightly to the LEFT (~15°)',
      'Turn your head slightly to the RIGHT (~15°)',
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Camera Lens Mode Indicator & Switch Camera
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.15)
                      : AppTheme.discordPurple.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isBack
                        ? Icons.camera_rear_rounded
                        : Icons.camera_front_rounded,
                    color: isBack
                        ? AppTheme.discordPurple
                        : AppTheme.discordYellow,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isBack ? 'BACK CAMERA (HD)' : 'FRONT CAMERA',
                    style: TextStyle(
                      color: isBack
                          ? AppTheme.discordPurple
                          : AppTheme.discordYellow,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: (isDark ? Colors.black : Colors.white).withOpacity(0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleCamera,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.cameraswitch_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Guidance Prompt Pill (Separated, no overlap on ticks!)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.discordPurple.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.discordPurple.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Step ${_faceIdStep + 1}/3: ',
                style: const TextStyle(
                    color: AppTheme.discordPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 11),
              ),
              Flexible(
                child: Text(
                  stepPrompts[_faceIdStep],
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Apple Face ID Circular Aperture & 36-Tick Radial Ring
        Center(
          child: SizedBox(
            width: 230,
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 194,
                    height: 194,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.previewSize?.height ?? 194,
                        height: controller.value.previewSize?.width ?? 194,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                ),
                CustomPaint(
                  size: const Size(230, 230),
                  painter: FaceIdRingPainter(
                    completedPoses: _faceIdEmbeddings.length,
                    currentStep: _faceIdStep,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Pose Status Badges
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPoseBadge(
                '1. Frontal', _faceIdEmbeddings.isNotEmpty, _faceIdStep == 0),
            const SizedBox(width: 6),
            _buildPoseBadge(
                '2. Left 15°', _faceIdEmbeddings.length >= 2, _faceIdStep == 1),
            const SizedBox(width: 6),
            _buildPoseBadge('3. Right 15°', _faceIdEmbeddings.length >= 3,
                _faceIdStep == 2),
          ],
        ),
      ],
    );
  }

  Widget _buildPoseBadge(String label, bool isDone, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDone
            ? AppTheme.discordGreen.withOpacity(0.2)
            : (isActive
                ? AppTheme.discordPurple.withOpacity(0.2)
                : Colors.black.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? AppTheme.discordGreen
              : (isActive ? AppTheme.discordPurple : Colors.white24),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.discordGreen, size: 12)
          else if (isActive)
            const Icon(Icons.radio_button_checked_rounded,
                color: AppTheme.discordPurple, size: 12)
          else
            const Icon(Icons.radio_button_unchecked_rounded,
                color: Colors.white38, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isDone
                  ? AppTheme.discordGreen
                  : (isActive ? AppTheme.discordPurple : Colors.white54),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardCameraPreview() {
    final controller = _controller;
    if (_error != null && controller == null) {
      return Center(child: Text(_error!));
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final isBack = _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),

          // Face Alignment Oval Guideline
          Center(
            child: Container(
              width: 200,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                border:
                    Border.all(color: Colors.white.withOpacity(0.5), width: 2),
              ),
            ),
          ),

          // Top Controls: Badge & Flip
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isBack
                            ? Icons.camera_rear_rounded
                            : Icons.camera_front_rounded,
                        color: isBack
                            ? AppTheme.discordPurple
                            : AppTheme.discordYellow,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isBack ? 'BACK CAMERA (HD)' : 'FRONT CAMERA',
                        style: TextStyle(
                          color: isBack
                              ? AppTheme.discordPurple
                              : AppTheme.discordYellow,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _toggleCamera,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.cameraswitch_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter that renders Apple Face ID-style 36 radial tick marks
/// that illuminate green as each 3D facial pose is acquired.
class FaceIdRingPainter extends CustomPainter {
  final int completedPoses; // 0, 1, 2, or 3
  final int currentStep; // 0, 1, or 2

  FaceIdRingPainter({required this.completedPoses, required this.currentStep});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const totalTicks = 36;

    final inactivePaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = AppTheme.discordPurple
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final completedPaint = Paint()
      ..color = AppTheme.discordGreen // Discord neon green
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < totalTicks; i++) {
      final angle = (i * 2 * pi / totalTicks) - (pi / 2);
      final tickStart = Offset(center.dx + (radius - 12) * cos(angle),
          center.dy + (radius - 12) * sin(angle));
      final tickEnd = Offset(
          center.dx + radius * cos(angle), center.dy + radius * sin(angle));

      // 12 ticks per sector (0..11: Frontal, 12..23: Left, 24..35: Right)
      final sector = i ~/ 12;
      Paint paintToUse;
      if (sector < completedPoses) {
        paintToUse = completedPaint;
      } else if (sector == currentStep) {
        paintToUse = activePaint;
      } else {
        paintToUse = inactivePaint;
      }

      canvas.drawLine(tickStart, tickEnd, paintToUse);
    }
  }

  @override
  bool shouldRepaint(FaceIdRingPainter oldDelegate) =>
      oldDelegate.completedPoses != completedPoses ||
      oldDelegate.currentStep != currentStep;
}
