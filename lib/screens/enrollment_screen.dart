import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/detection.dart';
import '../modules/pose_estimation/face_pose.dart';
import '../native/classroom_engine.dart';

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
    _controller?.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _captureAndEnroll() async {
    final controller = _controller;
    final name = _nameController.text.trim();
    if (controller == null || name.isEmpty) {
      setState(() => _error = 'Please enter a student name first.');
      return;
    }

    // Restrict duplicate names (case-insensitive)
    final isDuplicate = _enrolledStudents.any(
      (s) => (s['name'] as String? ?? '').trim().toLowerCase() == name.toLowerCase(),
    );
    if (isDuplicate) {
      setState(() {
        _error = 'Student "$name" is already enrolled. Please use a unique name.';
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
          _error = 'No face detected in the photo — try again with better lighting/framing.';
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
      setState(() => _error = 'Please enter a student name first.');
      return;
    }

    if (_faceIdStep == 0) {
      final isDuplicate = _enrolledStudents.any(
        (s) => (s['name'] as String? ?? '').trim().toLowerCase() == name.toLowerCase(),
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
          _error = 'No face detected! Center face in the Face ID ring and try again.';
        });
        return;
      }

      final pose = widget.engine.lastEnrollmentPose ??
          const FacePoseEstimator().estimatePose(
            Detection(frameId: 0, timestampSec: 0, bbox: [0, 0, 100, 100], confidence: 0.9, detector: 'yunet', detIndex: 0),
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
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
        const SnackBar(content: Text('No students to export! Enroll students first.')),
      );
      return;
    }
    try {
      final file = await widget.engine.exportClassroomRoster();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Classroom Roster Export: ${widget.engine.currentClassId} (${_enrolledStudents.length} Students with 512-d Face Embeddings)',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${_enrolledStudents.length} students from ${widget.engine.currentClassId}!')),
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
        final count = await widget.engine.importClassroomRoster(textController.text.trim());
        await _loadEnrolledStudents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully imported $count students into ${widget.engine.currentClassId}!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: Invalid roster format ($e)')),
          );
        }
      }
    }
  }

  void _showEnrolledListModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enrolled Students (${_enrolledStudents.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_enrolledStudents.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No students enrolled yet.', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _enrolledStudents.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = _enrolledStudents[i];
                          final id = s['student_id'] as String? ?? '';
                          final sName = s['name'] as String? ?? 'Unknown';
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(sName.isNotEmpty ? sName[0].toUpperCase() : '?'),
                            ),
                            title: Text(sName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('ID: $id'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                              tooltip: 'Delete $sName',
                              onPressed: () async {
                                await _deleteIndividualStudent(id, sName);
                                setModalState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Student'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export Classroom Roster',
            onPressed: _exportRoster,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            tooltip: 'Import Classroom Roster',
            onPressed: _showImportDialog,
          ),
          Badge(
            label: Text('${_enrolledStudents.length}'),
            isLabelVisible: _enrolledStudents.isNotEmpty,
            child: IconButton(
              icon: const Icon(Icons.people_alt_rounded),
              tooltip: 'View Enrolled Students',
              onPressed: _showEnrolledListModal,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear All Enrolled Faces',
            onPressed: () async {
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
                    const SnackBar(content: Text('All enrolled faces cleared. Roster is fresh!')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // Student Name Input
              TextField(
                controller: _nameController,
                style: const TextStyle(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'Student Name',
                  hintText: 'e.g. Athish Pranav',
                  prefixIcon: const Icon(Icons.person_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),

              // Mode Toggle: Face ID (Apple-Style) vs Quick 1-Shot
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isFaceIdMode = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _isFaceIdMode ? Theme.of(context).colorScheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.face_retouching_natural_rounded, size: 16, color: _isFaceIdMode ? Colors.white : Colors.white60),
                                const SizedBox(width: 6),
                                Text(
                                  '3D Face ID (3 Poses)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _isFaceIdMode ? Colors.white : Colors.white60,
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
                            color: !_isFaceIdMode ? Theme.of(context).colorScheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.camera_alt_rounded, size: 16, color: !_isFaceIdMode ? Colors.white : Colors.white60),
                                const SizedBox(width: 6),
                                Text(
                                  'Quick 1-Shot',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: !_isFaceIdMode ? Colors.white : Colors.white60,
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
              SizedBox(
                height: 340,
                child: _isFaceIdMode ? _buildFaceIdViewfinder() : _buildStandardCameraPreview(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
                        backgroundColor: _faceIdStep == 2 ? const Color(0xFF10B981) : Theme.of(context).colorScheme.primary,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isProcessing ? null : _captureFaceIdPose,
                      icon: _isProcessing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(_faceIdStep == 0
                              ? Icons.filter_center_focus_rounded
                              : (_faceIdStep == 1 ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded)),
                      label: Text(
                        _isProcessing
                            ? 'Processing Angle…'
                            : (_faceIdStep == 0
                                ? 'Capture Pose 1: Frontal'
                                : (_faceIdStep == 1
                                    ? 'Capture Pose 2: Turn Left'
                                    : 'Capture Pose 3: Turn Right & Finish')),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_faceIdStep > 0)
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _resetFaceId,
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('Restart Face ID Scan', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isProcessing ? null : _captureAndEnroll,
                  icon: _isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt_rounded),
                  label: Text(_isProcessing ? 'Processing…' : 'Capture & Enroll'),
                ),
            ],
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
      return const Center(child: CircularProgressIndicator());
    }

    final isBack = _cameras.isNotEmpty && _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    final stepPrompts = [
      'Look straight into the circle',
      'Turn your head slightly to the LEFT (~15°)',
      'Turn your head slightly to the RIGHT (~15°)',
    ];

    return Stack(
      alignment: Alignment.center,
      children: [
        // Camera Viewfinder masked in Circular Face ID Aperture
        Center(
          child: SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 210,
                    height: 210,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.previewSize?.height ?? 210,
                        height: controller.value.previewSize?.width ?? 210,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                ),

                // Apple Face ID 36-Tick Ring Painter
                CustomPaint(
                  size: const Size(246, 246),
                  painter: FaceIdRingPainter(
                    completedPoses: _faceIdEmbeddings.length,
                    currentStep: _faceIdStep,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Floating Camera Badge & Flip Toggle
        Positioned(
          top: 0,
          left: 4,
          right: 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBack ? Icons.camera_rear_rounded : Icons.camera_front_rounded,
                      color: isBack ? Colors.cyanAccent : Colors.orangeAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isBack ? 'BACK CAMERA (HD)' : 'FRONT CAMERA',
                      style: TextStyle(
                        color: isBack ? Colors.cyanAccent : Colors.orangeAccent,
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
                  child: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),

        // Guidance Prompt Pill at Top
        Positioned(
          top: 44,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Step ${_faceIdStep + 1}/3: ',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                Text(
                  stepPrompts[_faceIdStep],
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        // Angle Pills at Bottom of Circle
        Positioned(
          bottom: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPoseBadge('1. Frontal', _faceIdEmbeddings.isNotEmpty, _faceIdStep == 0),
              const SizedBox(width: 8),
              _buildPoseBadge('2. Left 15°', _faceIdEmbeddings.length >= 2, _faceIdStep == 1),
              const SizedBox(width: 8),
              _buildPoseBadge('3. Right 15°', _faceIdEmbeddings.length >= 3, _faceIdStep == 2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPoseBadge(String label, bool isDone, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xFF10B981).withOpacity(0.2)
            : (isActive ? Colors.cyanAccent.withOpacity(0.2) : Colors.black.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? const Color(0xFF10B981)
              : (isActive ? Colors.cyanAccent : Colors.white24),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12)
          else if (isActive)
            const Icon(Icons.radio_button_checked_rounded, color: Colors.cyanAccent, size: 12)
          else
            const Icon(Icons.radio_button_unchecked_rounded, color: Colors.white38, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isDone ? const Color(0xFF10B981) : (isActive ? Colors.cyanAccent : Colors.white54),
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

    final isBack = _cameras.isNotEmpty && _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;

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
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isBack ? Icons.camera_rear_rounded : Icons.camera_front_rounded,
                        color: isBack ? Colors.cyanAccent : Colors.orangeAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isBack ? 'BACK CAMERA (HD)' : 'FRONT CAMERA',
                        style: TextStyle(
                          color: isBack ? Colors.cyanAccent : Colors.orangeAccent,
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
                    child: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 18),
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
      ..color = Colors.cyanAccent
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final completedPaint = Paint()
      ..color = const Color(0xFF10B981) // Neon emerald green
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < totalTicks; i++) {
      final angle = (i * 2 * pi / totalTicks) - (pi / 2);
      final tickStart = Offset(center.dx + (radius - 12) * cos(angle), center.dy + (radius - 12) * sin(angle));
      final tickEnd = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));

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
      oldDelegate.completedPoses != completedPoses || oldDelegate.currentStep != currentStep;
}
