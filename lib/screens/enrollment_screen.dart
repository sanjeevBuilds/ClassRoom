import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../models/roster_entry.dart';
import '../modules/embedding_clustering/arcface_embedder.dart';
import '../modules/face_detection/yunet_detector.dart';
import '../modules/roster_matching/roster_db.dart';

/// Enrollment screen — adds a student to the local roster from a captured
/// photo. MVP simplification: one reference photo per student, taken here
/// (the real plan is multiple photos across angles/lighting).
///
/// Owner: Teammate 5 (Module 5)
class EnrollmentScreen extends StatefulWidget {
  final RosterDB rosterDb;
  final YuNetDetector detector;
  final ArcFaceEmbedder embedder;

  const EnrollmentScreen({
    super.key,
    required this.rosterDb,
    required this.detector,
    required this.embedder,
  });

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
      final frame = cv.imread(photo.path);

      final detections = await widget.detector.detect(
        frame,
        frameId: 0,
        timestampSec: 0,
      );
      if (detections.isEmpty) {
        setState(() {
          _error = 'No face detected in the photo — try again with better lighting/framing.';
          _isProcessing = false;
        });
        frame.release();
        return;
      }

      // Take the largest detected face (most likely the intended subject).
      detections.sort((a, b) {
        double area(List<double> box) => (box[2] - box[0]) * (box[3] - box[1]);
        return area(b.bbox).compareTo(area(a.bbox));
      });

      final embedding = await widget.embedder.extractEmbedding(frame, detections.first);
      frame.release();

      await widget.rosterDb.enrollStudent(RosterEntry(
        studentId: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        referenceEmbeddings: [embedding.vector],
      ));

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
      appBar: AppBar(title: const Text('Enroll Student')),
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
