import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _error = 'No camera found on this device.');
      return;
    }
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(front, ResolutionPreset.high, enableAudio: false);
    await controller.initialize();
    if (!mounted) return;
    setState(() => _controller = controller);
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enrolled $name.')));
      _nameController.clear();
    } catch (e) {
      setState(() => _error = 'Enrollment failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Student'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CameraPreview(controller),
    );
  }
}
