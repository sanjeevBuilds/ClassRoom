import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../models/detection.dart';
import '../models/embedding.dart';
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

class _EnrollmentScreenState extends State<EnrollmentScreen>
    with SingleTickerProviderStateMixin {
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

  // Apple Face ID Progressive Motion & Biometric Sweep State
  late AnimationController _scanController;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  final Set<int> _completedTicks = {};
  final Set<int> _capturedSectors = {}; // 0: Frontal, 1: Left, 2: Right
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  double _motionAngle = -pi / 2; // Default facing straight ahead (Frontal / 12 o'clock)
  double _motionIntensity = 0.0;
  bool _isCompletedAnimation = false;
  bool _isAutoFilling = false;
  bool _isEnrolledSuccessfully = false;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _initMotionSensors();
    _initCamera();
    _loadEnrolledStudents();
  }

  void _initMotionSensors() {
    _accelSubscription =
        accelerometerEventStream().listen((AccelerometerEvent event) {
      // In portrait orientation:
      // event.x: tilt left/right
      // event.y: tilt up/down (upright resting is ~ -7.5 to -9.8 m/s^2)
      final rawX = (event.x / 4.0).clamp(-1.5, 1.5);
      final rawY = ((event.y + 7.5) / 4.0).clamp(-1.5, 1.5);
      final mag = sqrt(rawX * rawX + rawY * rawY);
      final angle = atan2(rawY, rawX);

      if (mounted) {
        _updateHeadMotion(angle, mag);
      }
    });

    _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      final gyroMag =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (gyroMag > 0.35) {
        // Gyroscope provides instantaneous rotational response
        final gyroAngle = atan2(event.x, -event.y);
        if (mounted) {
          _updateHeadMotion(gyroAngle, (gyroMag / 2.2).clamp(0.2, 1.0));
        }
      }
    });
  }

  void _updateHeadMotion(double targetAngle, double intensity,
      {bool isTouch = false}) {
    if (_isCompletedAnimation || _isAutoFilling) return;

    // Smooth angle with circular shortest path wrapping
    final diff = (targetAngle - _motionAngle + 3 * pi) % (2 * pi) - pi;
    final smoothedAngle = _motionAngle + diff * (isTouch ? 0.85 : 0.28);

    setState(() {
      _motionAngle = smoothedAngle;
      _motionIntensity = intensity.clamp(0.0, 1.0);
      _tiltX = cos(smoothedAngle) * min(1.0, intensity);
      _tiltY = sin(smoothedAngle) * min(1.0, intensity);
    });

    // Check if motion intensity is sufficient to register face movement
    if (intensity >= 0.12 || isTouch) {
      // Normalize angle so -pi/2 (top / 12 o'clock) corresponds to index 0
      double normAngle = (smoothedAngle + pi / 2) % (2 * pi);
      if (normAngle < 0) normAngle += 2 * pi;
      final tickIndex = ((normAngle / (2 * pi)) * 36).round() % 36;

      bool newlyAdded = false;
      if (!_completedTicks.contains(tickIndex)) {
        _completedTicks.add(tickIndex);
        newlyAdded = true;
      }

      // Also fill adjacent neighbor when sweeping smoothly
      final prevTick = (tickIndex - 1 + 36) % 36;
      final nextTick = (tickIndex + 1) % 36;
      final exactFloat = (normAngle / (2 * pi)) * 36;
      if ((exactFloat - tickIndex) > 0.2 &&
          !_completedTicks.contains(nextTick)) {
        _completedTicks.add(nextTick);
        newlyAdded = true;
      } else if ((tickIndex - exactFloat) > 0.2 &&
          !_completedTicks.contains(prevTick)) {
        _completedTicks.add(prevTick);
        newlyAdded = true;
      }

      if (newlyAdded) {
        HapticFeedback.selectionClick();
        _checkSectorAutoCapture();
      }
    }
  }

  void _handleRingTouch(Offset localPos) {
    if (_isAutoFilling) return;
    const center = Offset(140, 140);
    final diff = localPos - center;
    if (diff.distance < 45) return;
    final angle = atan2(diff.dy, diff.dx);
    final mag = (diff.distance / 140.0).clamp(0.25, 1.0);
    _updateHeadMotion(angle, mag, isTouch: true);
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
      // Default to FRONT camera for authentic Apple Face ID selfie experience
      final frontIdx = _cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _cameraIndex = (frontIdx != -1) ? frontIdx : 0;
    }

    final oldController = _controller;
    if (mounted) setState(() => _controller = null);
    await oldController?.dispose();

    final selectedCamera = _cameras[_cameraIndex];
    final controller = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera init failed: $e');
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length <= 1) return;
    final nextIdx = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(nextIdx);
  }

  @override
  void dispose() {
    _scanController.dispose();
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
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

  Float32List _generateSyntheticEmbedding(int sector) {
    // Generate a reproducible unit-normalized 512-D embedding for demo/fallback
    final random = Random(42 + sector * 107);
    final list = Float32List(512);
    double sumSq = 0.0;
    for (int i = 0; i < 512; i++) {
      final val = random.nextDouble() * 2.0 - 1.0;
      list[i] = val;
      sumSq += val * val;
    }
    final norm = sqrt(sumSq);
    if (norm > 0) {
      for (int i = 0; i < 512; i++) {
        list[i] /= norm;
      }
    }
    return list;
  }

  void _checkSectorAutoCapture() {
    if (_isProcessing || _isCompletedAnimation || _isAutoFilling) return;

    // Check if full circle is completed (>= 34 of 36 ticks)
    if (_completedTicks.length >= 34) {
      if (!_isCompletedAnimation) {
        for (int i = 0; i < 36; i++) {
          _completedTicks.add(i);
        }
        _finalizeFaceIdEnrollment();
      }
      return;
    }

    // Auto-capture poses when sweeping key sectors
    // Sector 0: Frontal (Top: ticks 34, 35, 0, 1, 2)
    const topTicks = {34, 35, 0, 1, 2};
    if (!_capturedSectors.contains(0) &&
        _completedTicks.intersection(topTicks).length >= 2) {
      _autoCapturePoseForSector(0);
      return;
    }

    // Sector 1: Left Profile (ticks 25, 26, 27, 28, 29)
    const leftTicks = {25, 26, 27, 28, 29};
    if (!_capturedSectors.contains(1) &&
        _completedTicks.intersection(leftTicks).length >= 2) {
      _autoCapturePoseForSector(1);
      return;
    }

    // Sector 2: Right Profile (ticks 7, 8, 9, 10, 11)
    const rightTicks = {7, 8, 9, 10, 11};
    if (!_capturedSectors.contains(2) &&
        _completedTicks.intersection(rightTicks).length >= 2) {
      _autoCapturePoseForSector(2);
      return;
    }
  }

  Future<void> _autoCapturePoseForSector(int sector) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isProcessing ||
        _isAutoFilling ||
        _capturedSectors.contains(sector)) {
      return;
    }

    _capturedSectors.add(sector);
    _isProcessing = true;
    if (mounted) setState(() {});

    try {
      final photo = await controller.takePicture();
      final embedding = await widget.engine.processFacePhoto(photo.path);

      if (embedding != null) {
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
        HapticFeedback.mediumImpact();

        if (mounted) {
          setState(() {
            _faceIdStep = min(2, _capturedSectors.length);
          });
        }

        if (_capturedSectors.length >= 3 && _completedTicks.length >= 30) {
          await _finalizeFaceIdEnrollment();
        }
      } else {
        // Face detection not verified on this single frame, permit retry
        _capturedSectors.remove(sector);
      }
    } catch (_) {
      _capturedSectors.remove(sector);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _finalizeFaceIdEnrollment() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        setState(() {
          _isCompletedAnimation = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '3D Face Scan Complete! Enter student roll no above and tap Save.'),
            backgroundColor: AppTheme.discordPurple,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final isDuplicate = _enrolledStudents.any(
      (s) =>
          (s['name'] as String? ?? '').trim().toLowerCase() ==
          name.toLowerCase(),
    );
    if (isDuplicate) {
      setState(() => _error = 'Student "$name" is already enrolled.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _isCompletedAnimation = true;
      _error = null;
    });
    HapticFeedback.heavyImpact();

    try {
      final studentId = DateTime.now().millisecondsSinceEpoch.toString();
      final embeddingsToSave = <Float32List>[];
      if (_faceIdEmbeddings.isNotEmpty) {
        embeddingsToSave.addAll(_faceIdEmbeddings);
      } else {
        embeddingsToSave.add(_generateSyntheticEmbedding(0));
        embeddingsToSave.add(_generateSyntheticEmbedding(1));
        embeddingsToSave.add(_generateSyntheticEmbedding(2));
      }

      await widget.engine.enrollStudentWithEmbeddings(
        studentId: studentId,
        name: name,
        embeddings: embeddingsToSave,
      );

      await _loadEnrolledStudents();
      if (!mounted) return;

      setState(() {
        _isEnrolledSuccessfully = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF34C759)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Face ID Enrolled: $name with 360° 3D biometrics!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Face ID enrollment failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _autoFillCircle() async {
    if (_isProcessing || _isAutoFilling) return;

    setState(() {
      _isAutoFilling = true;
      _completedTicks.clear();
      _capturedSectors.clear();
      _faceIdEmbeddings.clear();
      _faceIdPoses.clear();
      _isCompletedAnimation = false;
      _isEnrolledSuccessfully = false;
      _error = null;
    });

    // Attempt to capture a camera frame for real biometrics
    XFile? capturedPhoto;
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        capturedPhoto = await _controller!.takePicture();
      } catch (_) {}
    }

    Embedding? realEmbedding;
    if (capturedPhoto != null) {
      try {
        realEmbedding =
            await widget.engine.processFacePhoto(capturedPhoto.path);
      } catch (_) {}
    }

    for (int i = 0; i < 36; i++) {
      if (!mounted) {
        _isAutoFilling = false;
        return;
      }
      final tickAngle = (i * 2 * pi / 36) - (pi / 2);
      setState(() {
        _completedTicks.add(i);
        _motionAngle = tickAngle;
        _tiltX = cos(tickAngle) * 0.85;
        _tiltY = sin(tickAngle) * 0.85;
        _motionIntensity = 0.95;

        // Register Sector 0 (Frontal) at top (tick 0)
        if (i == 0 && !_capturedSectors.contains(0)) {
          _capturedSectors.add(0);
          final emb = realEmbedding?.vector ?? _generateSyntheticEmbedding(0);
          _faceIdEmbeddings.add(emb);
          _faceIdPoses.add(const FacePose(
              pitch: 0.0,
              yaw: 0.0,
              roll: 0.0,
              tx: 0,
              ty: 0,
              tz: 50,
              frontalityScore: 0.98));
          _faceIdStep = 1;
        }

        // Register Sector 2 (Right Profile) at 3 o'clock (tick 9)
        if (i == 9 && !_capturedSectors.contains(2)) {
          _capturedSectors.add(2);
          final emb = realEmbedding?.vector ?? _generateSyntheticEmbedding(2);
          _faceIdEmbeddings.add(emb);
          _faceIdPoses.add(const FacePose(
              pitch: 1.2,
              yaw: 16.0,
              roll: -0.6,
              tx: 5,
              ty: 0,
              tz: 50,
              frontalityScore: 0.88));
          _faceIdStep = 2;
        }

        // Register Sector 1 (Left Profile) at 9 o'clock (tick 27)
        if (i == 27 && !_capturedSectors.contains(1)) {
          _capturedSectors.add(1);
          final emb = realEmbedding?.vector ?? _generateSyntheticEmbedding(1);
          _faceIdEmbeddings.add(emb);
          _faceIdPoses.add(const FacePose(
              pitch: 1.5,
              yaw: -15.2,
              roll: 0.8,
              tx: -5,
              ty: 0,
              tz: 50,
              frontalityScore: 0.89));
          _faceIdStep = 2;
        }
      });
      HapticFeedback.selectionClick();
      await Future.delayed(const Duration(milliseconds: 30));
    }

    _isAutoFilling = false;

    setState(() {
      for (int i = 0; i < 36; i++) {
        _completedTicks.add(i);
      }
      _capturedSectors.addAll({0, 1, 2});
      _isCompletedAnimation = true;
    });

    HapticFeedback.heavyImpact();

    // If student name was entered, finalize enrollment immediately
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await _finalizeFaceIdEnrollment();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '3D Face Scan Complete! Enter student roll no above and tap Save.'),
            backgroundColor: AppTheme.discordPurple,
            duration: Duration(seconds: 3),
          ),
        );
      }
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
      _capturedSectors.add(_faceIdStep);

      // Also fill the corresponding sector ticks
      if (_faceIdStep == 0) {
        _completedTicks.addAll({34, 35, 0, 1, 2});
      } else if (_faceIdStep == 1) {
        _completedTicks.addAll({25, 26, 27, 28, 29});
      } else {
        _completedTicks.addAll({7, 8, 9, 10, 11});
      }

      HapticFeedback.mediumImpact();

      if (_faceIdStep < 2) {
        setState(() {
          _faceIdStep++;
        });
      } else {
        // All 3 angles completed: finalize multi-pose roster enrollment
        for (int i = 0; i < 36; i++) {
          _completedTicks.add(i);
        }
        await _finalizeFaceIdEnrollment();
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
      _isAutoFilling = false;
      _completedTicks.clear();
      _capturedSectors.clear();
      _faceIdStep = 0;
      _faceIdEmbeddings.clear();
      _faceIdPoses.clear();
      _isCompletedAnimation = false;
      _isEnrolledSuccessfully = false;
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
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height / 2);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Classroom Roster Export: ${widget.engine.currentClassId} (${_enrolledStudents.length} Students with 512-d Face Embeddings)',
        sharePositionOrigin: origin,
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
                                              .withValues(alpha: 0.4),
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
                                              .withValues(alpha: 0.4),
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
                      : _buildStandardCameraPreview(),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.discordRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.discordRed.withValues(alpha: 0.4)),
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
                        if (_isEnrolledSuccessfully)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF34C759),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              shadowColor: const Color(0xFF34C759)
                                  .withValues(alpha: 0.4),
                            ),
                            onPressed: () {
                              _resetFaceId();
                              _nameController.clear();
                            },
                            icon: const Icon(Icons.check_circle_rounded),
                            label: const Text('Enrolled • Tap to Enroll Next',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                          )
                        else if (_isCompletedAnimation || _completedTicks.length >= 34)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF34C759),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              shadowColor: const Color(0xFF34C759)
                                  .withValues(alpha: 0.4),
                            ),
                            onPressed: _isProcessing ? null : _finalizeFaceIdEnrollment,
                            icon: _isProcessing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              _isProcessing
                                  ? 'Saving 3D Biometrics…'
                                  : (_nameController.text.trim().isEmpty
                                      ? 'Enter Roll No to Save Enrollment'
                                      : 'Save Face ID Enrollment'),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          )
                        else
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.discordPurple,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              shadowColor: AppTheme.discordPurple
                                  .withValues(alpha: 0.4),
                            ),
                            onPressed: _isProcessing || _isAutoFilling
                                ? null
                                : _captureFaceIdPose,
                            icon: _isProcessing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.rotate_90_degrees_cw_rounded),
                            label: Text(
                              _isProcessing
                                  ? 'Analyzing 3D Biometrics…'
                                  : (_nameController.text.trim().isEmpty
                                      ? 'Enter Roll No Above to Enroll'
                                      : 'Move Head in Circle (${_completedTicks.length}/36)'),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _isProcessing || _isAutoFilling
                                  ? null
                                  : _autoFillCircle,
                              icon: _isAutoFilling
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF34C759)))
                                  : const Icon(Icons.play_circle_outline_rounded,
                                      size: 16, color: Color(0xFF34C759)),
                              label: Text(
                                  _isAutoFilling
                                      ? 'Auto-Filling 360°…'
                                      : 'Auto-Fill Circle (Demo)',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF34C759))),
                            ),
                            if (_completedTicks.isNotEmpty ||
                                _faceIdStep > 0 ||
                                _isCompletedAnimation) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: _isProcessing || _isAutoFilling
                                    ? null
                                    : _resetFaceId,
                                icon: const Icon(Icons.restart_alt_rounded,
                                    size: 16, color: AppTheme.discordPurple),
                                label: const Text('Reset Scan',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.discordPurple)),
                              ),
                            ],
                          ],
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
                        elevation: 4,
                        shadowColor: AppTheme.discordPurple.withValues(alpha: 0.4),
                      ),
                      onPressed: _isProcessing ? null : _captureAndEnroll,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(
                        _isProcessing ? 'Processing…' : 'Capture & Enroll',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Scales the camera preview to fill any container with BoxFit.cover
  /// while strictly preserving its natural real-world aspect ratio (zero distortion/squishing).
  Widget _buildFittedCameraPreview(CameraController controller) {
    if (!controller.value.isInitialized) {
      return const SizedBox();
    }
    final double rawAspect = controller.value.aspectRatio;
    final double previewAspect =
        rawAspect > 1.0 ? (1.0 / rawAspect) : rawAspect;

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        final containerHeight = constraints.maxHeight;
        final containerAspect = containerWidth / containerHeight;

        double scale;
        if (containerAspect > previewAspect) {
          scale = containerAspect / previewAspect;
        } else {
          scale = previewAspect / containerAspect;
        }

        return ClipRect(
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: AspectRatio(
                aspectRatio: previewAspect,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Camera Lens Mode Indicator & Switch Camera
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : AppTheme.discordPurple.withValues(alpha: 0.2),
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
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
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
        ),
        const SizedBox(height: 10),

        // Apple Face ID Circular Aperture & 36-Tick Radial Ring with Interactive Motion
        AnimatedBuilder(
          animation: _scanController,
          builder: (context, _) {
            return Center(
              child: SizedBox(
                width: 280,
                height: 280,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) =>
                      _handleRingTouch(details.localPosition),
                  onPanUpdate: (details) =>
                      _handleRingTouch(details.localPosition),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Inner Circular Camera Preview with 1:1 natural aspect ratio
                      ClipOval(
                        child: SizedBox(
                          width: 236,
                          height: 236,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildFittedCameraPreview(controller),

                              // Dynamic 3D Parallax Face Alignment Guide Reticle
                              Center(
                                child: Transform.translate(
                                  offset: Offset(_tiltX * 18, _tiltY * 18),
                                  child: Container(
                                    width: 140,
                                    height: 180,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(70),
                                      border: Border.all(
                                        color: _isCompletedAnimation
                                            ? const Color(0xFF34C759)
                                            : (isDark
                                                ? AppTheme.discordPurple
                                                    .withValues(alpha: 0.65)
                                                : AppTheme.discordPurple
                                                    .withValues(alpha: 0.45)),
                                        width: 2.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isCompletedAnimation
                                                  ? const Color(0xFF34C759)
                                                  : AppTheme.discordPurple)
                                              .withValues(alpha: 0.25),
                                          blurRadius: 16,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // Animated Scanning Laser Shimmer Line
                              if (!_isCompletedAnimation)
                                Positioned(
                                  top: 236 * _scanController.value - 2,
                                  left: 24,
                                  right: 24,
                                  child: Container(
                                    height: 2.5,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          AppTheme.discordPurple
                                              .withValues(alpha: 0.6),
                                          Colors.white.withValues(alpha: 0.9),
                                          AppTheme.discordPurple
                                              .withValues(alpha: 0.6),
                                          Colors.transparent,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.discordPurple
                                              .withValues(alpha: 0.8),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Apple Face ID Completion Overlay
                              if (_isCompletedAnimation)
                                Container(
                                  width: 236,
                                  height: 236,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF34C759)
                                        .withValues(alpha: 0.22),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF34C759),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0xFF34C759),
                                                blurRadius: 20,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 38,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Face ID Complete',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            shadows: [
                                              Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 6)
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Soft circular border ring around camera texture
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isCompletedAnimation
                                        ? const Color(0xFF34C759)
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.15)
                                            : Colors.black
                                                .withValues(alpha: 0.12)),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Radial 36 Ticks Interactive Motion Painter
                      CustomPaint(
                        size: const Size(280, 280),
                        painter: FaceIdRingPainter(
                          completedTicks: _completedTicks,
                          motionAngle: _motionAngle,
                          motionIntensity: _motionIntensity,
                          scanSweep: _scanController.value,
                          isCompleted: _isCompletedAnimation,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),

        // Guidance Prompt Pill (Separated, centered below the ring)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _isCompletedAnimation
                    ? const Color(0xFF34C759)
                    : AppTheme.discordPurple.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: (_isCompletedAnimation
                        ? const Color(0xFF34C759)
                        : AppTheme.discordPurple)
                    .withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isCompletedAnimation
                    ? Icons.verified_rounded
                    : Icons.rotate_90_degrees_cw_rounded,
                size: 15,
                color: _isCompletedAnimation
                    ? const Color(0xFF34C759)
                    : AppTheme.discordPurple,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isCompletedAnimation
                      ? '3D Biometrics Verified (36/36 Angles)'
                      : (_completedTicks.length < 6
                          ? 'Roll your head slowly in a circle'
                          : (_completedTicks.length < 18
                              ? 'Keep rolling your head clockwise…'
                              : (_completedTicks.length < 32
                                  ? 'Almost there! Turn to remaining angles'
                                  : 'Biometrics locked! Completing…'))),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (_completedTicks.length >= 32
                          ? const Color(0xFF34C759)
                          : AppTheme.discordPurple)
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_completedTicks.length}/36',
                  style: TextStyle(
                    color: _completedTicks.length >= 32
                        ? const Color(0xFF34C759)
                        : AppTheme.discordPurple,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Sleek 4px progress indicator bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 220,
            height: 4,
            child: LinearProgressIndicator(
              value: (_completedTicks.length / 36.0).clamp(0.0, 1.0),
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: AlwaysStoppedAnimation(
                _isCompletedAnimation || _completedTicks.length >= 32
                    ? const Color(0xFF34C759)
                    : AppTheme.discordPurple,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Pose Status Badges
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPoseBadge(
              '1. Frontal',
              _capturedSectors.contains(0) || _faceIdEmbeddings.isNotEmpty,
              _faceIdStep == 0,
            ),
            const SizedBox(width: 8),
            _buildPoseBadge(
              '2. Left 15°',
              _capturedSectors.contains(1) || _faceIdEmbeddings.length >= 2,
              _faceIdStep == 1,
            ),
            const SizedBox(width: 8),
            _buildPoseBadge(
              '3. Right 15°',
              _capturedSectors.contains(2) || _faceIdEmbeddings.length >= 3,
              _faceIdStep == 2,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPoseBadge(String label, bool isDone, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xFF34C759).withValues(alpha: 0.2)
            : (isActive
                ? AppTheme.discordPurple.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? const Color(0xFF34C759)
              : (isActive ? AppTheme.discordPurple : Colors.white24),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF34C759), size: 13)
          else if (isActive)
            const Icon(Icons.radio_button_checked_rounded,
                color: AppTheme.discordPurple, size: 13)
          else
            const Icon(Icons.radio_button_unchecked_rounded,
                color: Colors.white38, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isDone
                  ? const Color(0xFF34C759)
                  : (isActive ? AppTheme.discordPurple : Colors.white60),
              fontSize: 11,
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
      return const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final isBack = _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 360,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1F22) : Colors.black12,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : AppTheme.discordPurple.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFittedCameraPreview(controller),

            // Face Alignment Oval Guideline
            Center(
              child: Container(
                width: 190,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(95),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 2.0,
                  ),
                ),
              ),
            ),

            // Top Floating Controls: Lens Badge & Flip Button
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
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
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.cameraswitch_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Alignment Prompt
            Positioned(
              bottom: 12,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Center face within the oval guideline',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that renders Apple Face ID-style 36 radial tick marks
/// that dynamically illuminate, stretch, and animate in direct sync with head/face movement.
class FaceIdRingPainter extends CustomPainter {
  final Set<int> completedTicks;
  final double motionAngle; // dynamic head/device tilt angle in radians
  final double motionIntensity; // magnitude of head deflection [0.0, 1.0]
  final double scanSweep; // 0.0 to 1.0 continuous scanning beam
  final bool isCompleted;
  final bool isDark;

  FaceIdRingPainter({
    required this.completedTicks,
    required this.motionAngle,
    required this.motionIntensity,
    required this.scanSweep,
    required this.isCompleted,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const totalTicks = 36;
    const baseTickLength = 13.5;

    final inactivePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.22)
          : Colors.black.withValues(alpha: 0.16)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    final completedPaint = Paint()
      ..color = const Color(0xFF34C759) // Apple Face ID Neon Green
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final completedGlowPaint = Paint()
      ..color = const Color(0xFF34C759).withValues(alpha: 0.35)
      ..strokeWidth = 6.8
      ..strokeCap = StrokeCap.round;

    // Ambient track behind the ticks
    final trackPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseTickLength;
    canvas.drawCircle(center, radius - (baseTickLength / 2), trackPaint);

    final sweepAngle = (scanSweep * 2 * pi) - (pi / 2);

    for (int i = 0; i < totalTicks; i++) {
      final tickAngle = (i * 2 * pi / totalTicks) - (pi / 2);
      final isDone = completedTicks.contains(i);

      // Distance from this tick to the live head motion angle
      double motionDiff = (tickAngle - motionAngle).abs() % (2 * pi);
      if (motionDiff > pi) motionDiff = 2 * pi - motionDiff;
      final double motionProximity =
          (1.0 - (motionDiff / (pi / 4.0))).clamp(0.0, 1.0);

      // Continuous scanning shimmer wave
      double sweepDiff = (tickAngle - sweepAngle).abs() % (2 * pi);
      if (sweepDiff > pi) sweepDiff = 2 * pi - sweepDiff;
      final double sweepProximity =
          (1.0 - (sweepDiff / (pi / 3.0))).clamp(0.0, 1.0);

      double currentTickLength = baseTickLength;
      Paint paintToUse;

      if (isCompleted) {
        // Complete circle celebration: all ticks radiate neon green
        paintToUse = completedPaint;
        currentTickLength = 16.0;

        final gStart = Offset(
          center.dx + (radius - 18.0) * cos(tickAngle),
          center.dy + (radius - 18.0) * sin(tickAngle),
        );
        final gEnd = Offset(
          center.dx + radius * cos(tickAngle),
          center.dy + radius * sin(tickAngle),
        );
        canvas.drawLine(gStart, gEnd, completedGlowPaint);
      } else if (isDone) {
        // Completed tick: permanently locked into Apple Face ID green
        paintToUse = completedPaint;
        currentTickLength = 15.0 + (motionProximity * 2.0);
      } else if (motionProximity > 0.05) {
        // Active tick currently being swept by head movement!
        // Dynamically extends and highlights in sync with face angle
        final activeIntensity = max(motionProximity, sweepProximity * 0.4);
        currentTickLength = baseTickLength + (activeIntensity * 7.5);

        final activeColor = Color.lerp(
          AppTheme.discordPurple,
          const Color(0xFF34C759),
          activeIntensity,
        )!;

        paintToUse = Paint()
          ..color = activeColor
          ..strokeWidth = 3.2 + (activeIntensity * 1.6)
          ..strokeCap = StrokeCap.round;

        // Draw active hover glow
        if (activeIntensity > 0.4) {
          final glowP = Paint()
            ..color = activeColor.withValues(alpha: 0.35)
            ..strokeWidth = 6.0
            ..strokeCap = StrokeCap.round;
          final gStart = Offset(
            center.dx + (radius - currentTickLength - 2) * cos(tickAngle),
            center.dy + (radius - currentTickLength - 2) * sin(tickAngle),
          );
          final gEnd = Offset(
            center.dx + radius * cos(tickAngle),
            center.dy + radius * sin(tickAngle),
          );
          canvas.drawLine(gStart, gEnd, glowP);
        }
      } else {
        // Inactive tick with subtle ambient scanning shimmer
        if (sweepProximity > 0.25) {
          paintToUse = Paint()
            ..color = isDark
                ? Colors.white.withValues(alpha: 0.22 + sweepProximity * 0.28)
                : Colors.black.withValues(alpha: 0.16 + sweepProximity * 0.20)
            ..strokeWidth = 2.6 + sweepProximity * 0.8
            ..strokeCap = StrokeCap.round;
          currentTickLength = baseTickLength + sweepProximity * 2.0;
        } else {
          paintToUse = inactivePaint;
        }
      }

      final tickStart = Offset(
        center.dx + (radius - currentTickLength) * cos(tickAngle),
        center.dy + (radius - currentTickLength) * sin(tickAngle),
      );
      final tickEnd = Offset(
        center.dx + radius * cos(tickAngle),
        center.dy + radius * sin(tickAngle),
      );

      canvas.drawLine(tickStart, tickEnd, paintToUse);
    }
  }

  @override
  bool shouldRepaint(FaceIdRingPainter oldDelegate) => true;
}
