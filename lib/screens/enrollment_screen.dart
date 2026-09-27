import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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
    if (controller == null || name.isEmpty) return;

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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Student name', border: OutlineInputBorder()),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildCameraPreview()),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isProcessing ? null : _captureAndEnroll,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt_rounded),
              label: Text(_isProcessing ? 'Processing…' : 'Capture & Enroll'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
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
              width: 220,
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(110),
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 2,
                ),
              ),
            ),
          ),

          // Top Controls Overlay: Camera Badge & Flip Button
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
                        isBack ? 'BACK CAMERA (6-AXIS HD)' : 'FRONT CAMERA',
                        style: TextStyle(
                          color: isBack ? Colors.cyanAccent : Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
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
                    child: const Icon(
                      Icons.cameraswitch_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 6-Axis Pose Telemetry Banner (if available)
          if (_lastPose != null)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Pitch: ${_lastPose!.pitch.toStringAsFixed(1)}°',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Text(
                      'Yaw: ${_lastPose!.yaw.toStringAsFixed(1)}°',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Text(
                      'Roll: ${_lastPose!.roll.toStringAsFixed(1)}°',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Text(
                      'Frontality: ${(_lastPose!.frontalityScore * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
