import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'processing_screen.dart';

class CaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final ClassroomEngine engine;

  const CaptureScreen({super.key, required this.cameras, required this.engine});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

/// Immutable snapshot of device motion for zero-jank 120Hz guideline rendering.
class GyroGuidelineState {
  final double panPosition;   // 0.0 to 1.0 (horizontal position across reticle)
  final double rollAngle;     // radians (tilt left/right)
  final double pitchOffset;   // pixels (tilt up/down)
  final double panVelocity;   // rad/s (instantaneous yaw rate)
  final bool isMovingTooFast; // speed > 1.5 rad/s
  final bool isLevel;         // rollAngle.abs() < 0.035 (~2 degrees)

  const GyroGuidelineState({
    this.panPosition = 0.5,
    this.rollAngle = 0.0,
    this.pitchOffset = 0.0,
    this.panVelocity = 0.0,
    this.isMovingTooFast = false,
    this.isLevel = true,
  });
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _accelSubscription;
  late AnimationController _guideAnimController;
  final ValueNotifier<GyroGuidelineState> _gyroGuidelineNotifier =
      ValueNotifier<GyroGuidelineState>(const GyroGuidelineState());

  bool _isMovingTooFast = false;
  bool _isRecording = false;
  bool _isTorchOn = false;
  bool _isPickingVideo = false;

  // Real-time motion tracking state
  int _lastGyroTime = 0;
  double _panPosition = 0.5;
  double _previewPanAngle = 0.0;
  double _recordingPanAngle = 0.0;
  double _currentYawVelocity = 0.0;
  double _smoothedRoll = 0.0;
  double _pitchOffset = 0.0;
  bool _isDeviceLevel = true;
  double _lastAccelX = 0.0;
  double _lastAccelY = -9.8;
  double _lastAccelZ = 0.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _guideAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _initCamera();
    _initSensors();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    // Select back camera if available for highest resolution sweep
    final camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final oldController = _controller;
    if (mounted) setState(() => _controller = null);
    await oldController?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.veryHigh, // 1080p Full HD for crisp face detection across classroom
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera init error: $e')),
        );
      }
    }
  }

  void _initSensors() {
    _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      final speed = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final tooFast = speed > 1.5;

      final now = DateTime.now().microsecondsSinceEpoch;
      if (_lastGyroTime == 0) {
        _lastGyroTime = now;
        return;
      }
      final dt = ((now - _lastGyroTime) / 1000000.0).clamp(0.001, 0.05);
      _lastGyroTime = now;

      // World-gravity projected yaw:
      // Project angular velocity onto gravity normal vector so horizontal panning
      // moves the guideline accurately in portrait, even when camera is angled downward at desks.
      final gNorm = sqrt(_lastAccelX * _lastAccelX + _lastAccelY * _lastAccelY + _lastAccelZ * _lastAccelZ);
      final double yawRate;
      if (gNorm > 2.0) {
        yawRate = -(_lastAccelX * event.x + _lastAccelY * event.y + _lastAccelZ * event.z) / gNorm;
      } else {
        yawRate = -event.y;
      }
      _currentYawVelocity = yawRate;

      if (_isRecording) {
        // Accumulate pan motion across the classroom sweep
        _recordingPanAngle += yawRate * dt;
        // ~55 degrees (0.95 rad) represents sweeping a standard classroom row
        _panPosition = (0.15 + (_recordingPanAngle / 0.95) * 0.70).clamp(0.05, 0.95);
      } else {
        // In preview mode: moves guideline dynamically in the physical direction of rotation
        _previewPanAngle += yawRate * dt;
        // Natural spring damping back to center
        _previewPanAngle *= (1.0 - 0.8 * dt);
        _previewPanAngle = _previewPanAngle.clamp(-0.55, 0.55);
        _panPosition = (0.5 + (_previewPanAngle / 0.55) * 0.44).clamp(0.05, 0.95);
      }

      if (tooFast != _isMovingTooFast) {
        setState(() => _isMovingTooFast = tooFast);
      }

      _notifyGyroUpdate();
    });

    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      _lastAccelX = event.x;
      _lastAccelY = event.y;
      _lastAccelZ = event.z;

      // 1. Roll angle (left/right tilt)
      // Only compute roll tilt when phone is held in portrait (downward gravity on Y axis)
      // and strictly clamp to max ±9 degrees so guideline NEVER flips into landscape
      final double rawRoll;
      if (-event.y > 2.5) {
        rawRoll = atan2(event.x, -event.y).clamp(-0.16, 0.16);
      } else {
        rawRoll = 0.0;
      }
      _smoothedRoll += (rawRoll - _smoothedRoll) * 0.28;
      final isLevel = _smoothedRoll.abs() < 0.035; // ~2 degrees

      // 2. Pitch angle (up/down elevation tilt)
      final rawPitch = atan2(event.z, sqrt(event.x * event.x + event.y * event.y));
      final pitchDelta = rawPitch - 0.08; // Natural upright holding angle offset
      _pitchOffset = (pitchDelta * 45.0).clamp(-22.0, 22.0);
      _isDeviceLevel = isLevel;

      _notifyGyroUpdate();
    });
  }

  void _notifyGyroUpdate() {
    _gyroGuidelineNotifier.value = GyroGuidelineState(
      panPosition: _panPosition,
      rollAngle: _smoothedRoll,
      pitchOffset: _pitchOffset,
      panVelocity: _currentYawVelocity,
      isMovingTooFast: _isMovingTooFast,
      isLevel: _isDeviceLevel,
    );
  }

  @override
  void dispose() {
    _guideAnimController.dispose();
    _gyroSubscription?.cancel();
    _accelSubscription?.cancel();
    _gyroGuidelineNotifier.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final next = !_isTorchOn;
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _isTorchOn = next);
    } catch (_) {}
  }

  Future<void> _pickVideoFromGallery() async {
    if (_isRecording || _isPickingVideo) return;
    setState(() => _isPickingVideo = true);

    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (picked != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(
              videoPath: picked.path,
              engine: widget.engine,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load video: $e'),
            backgroundColor: AppTheme.discordRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingVideo = false);
    }
  }

  void _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      final file = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(videoPath: file.path, engine: widget.engine),
          ),
        );
      }
    } else {
      _recordingPanAngle = 0.0; // Reset pan accumulator for fresh row sweep
      _panPosition = 0.15;      // Start near left edge to sweep towards right
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
      _notifyGyroUpdate();
    }
  }

  /// Scales camera preview to cover the entire screen while strictly preserving
  /// the true hardware sensor aspect ratio (zero squishing/distortion).
  Widget _buildFullscreenCameraPreview(BuildContext context, CameraController controller) {
    final size = MediaQuery.of(context).size;
    final double rawAspect = controller.value.aspectRatio;
    final double previewAspect = rawAspect > 1.0 ? (1.0 / rawAspect) : rawAspect;

    var scale = size.aspectRatio / previewAspect;
    if (scale < 1) scale = 1 / scale;

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
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.discordPurple),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fullscreen Distortion-Free Camera Preview
          _buildFullscreenCameraPreview(context, _controller!),

          // Sweep Reticle & Guidelines Overlay (driven directly by Gyroscope & Accelerometer)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_gyroGuidelineNotifier, _guideAnimController]),
                builder: (context, _) {
                  final gyroState = _gyroGuidelineNotifier.value;
                  return CustomPaint(
                    painter: ClassroomSweepGuidelinePainter(
                      panPosition: gyroState.panPosition,
                      rollAngle: gyroState.rollAngle,
                      pitchOffset: gyroState.pitchOffset,
                      panVelocity: gyroState.panVelocity,
                      animShimmer: _guideAnimController.value,
                      isRecording: _isRecording,
                      isMovingTooFast: gyroState.isMovingTooFast,
                      isLevel: gyroState.isLevel,
                    ),
                  );
                },
              ),
            ),
          ),

          // Guideline Instruction HUD Pill (Real-Time Motion Feedback)
          Positioned(
            left: 0,
            right: 0,
            top: (MediaQuery.of(context).size.height * 0.72) - 15,
            child: Center(
              child: IgnorePointer(
                child: ValueListenableBuilder<GyroGuidelineState>(
                  valueListenable: _gyroGuidelineNotifier,
                  builder: (context, gyroState, _) {
                    final isMovingTooFast = gyroState.isMovingTooFast;
                    final isLevel = gyroState.isLevel;
                    final isPanning = gyroState.panVelocity.abs() > 0.15;

                    IconData icon;
                    String text;
                    Color color;

                    if (isMovingTooFast) {
                      icon = Icons.warning_amber_rounded;
                      text = 'Slow down • Panning too fast';
                      color = AppTheme.discordRed;
                    } else if (!isLevel) {
                      final deg = (gyroState.rollAngle * 180 / pi).abs().round();
                      icon = Icons.screen_rotation_rounded;
                      text = 'Tilt phone $deg° to level with desk rows';
                      color = AppTheme.discordYellow;
                    } else if (_isRecording) {
                      icon = Icons.fiber_manual_record_rounded;
                      text = isPanning
                          ? 'Sweeping row • Keep steady'
                          : 'Sweep across row from left to right';
                      color = const Color(0xFF57F287);
                    } else {
                      icon = Icons.straighten_rounded;
                      text = 'Phone level • Sweep across classroom rows';
                      color = AppTheme.discordLightPurple;
                    }

                    return GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      borderRadius: 20,
                      borderColor: color.withValues(alpha: 0.4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 14, color: color),
                          const SizedBox(width: 8),
                          Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Sweep Guidance Overlay
          if (_isMovingTooFast && _isRecording)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _isMovingTooFast ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: AppTheme.discordRed.withValues(alpha: 0.3),
                  child: Center(
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      borderColor: AppTheme.discordRed.withValues(alpha: 0.6),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 64, color: AppTheme.discordRed),
                          SizedBox(height: 16),
                          Text(
                            'SLOW DOWN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Panning too fast causes motion blur',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Top Controls Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.all(4),
                      borderRadius: 14,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        borderRadius: 14,
                        child: Row(
                          children: [
                            Icon(
                              Icons.panorama_photosphere_outlined,
                              size: 16,
                              color: _isRecording ? AppTheme.discordRed : AppTheme.discordPurple,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isRecording ? 'Sweeping Classroom…' : 'Sweep across classroom',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_isRecording)
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        borderColor: AppTheme.discordRed.withValues(alpha: 0.5),
                        borderRadius: 14,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record, color: AppTheme.discordRed, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'REC',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _pickVideoFromGallery,
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          borderRadius: 14,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.upload_file_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Upload',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Controls: Upload Video Button | Shutter / Record | Torch Toggle
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Upload Video from Gallery Button
                    GestureDetector(
                      onTap: _isRecording ? null : _pickVideoFromGallery,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.video_library_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),

                    // Main Sweep Video Recording Trigger
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isRecording ? AppTheme.discordRed : AppTheme.discordPurple,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isRecording ? AppTheme.discordRed : AppTheme.discordPurple).withValues(alpha: 0.4),
                              blurRadius: 22,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _isRecording ? 32 : 66,
                            height: _isRecording ? 32 : 66,
                            decoration: BoxDecoration(
                              color: _isRecording ? AppTheme.discordRed : AppTheme.discordPurple,
                              borderRadius: BorderRadius.circular(_isRecording ? 8 : 33),
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop_rounded : Icons.videocam_rounded,
                              color: Colors.white,
                              size: _isRecording ? 20 : 32,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Torch / Flash Toggle Button
                    GestureDetector(
                      onTap: _toggleTorch,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _isTorchOn
                              ? AppTheme.discordYellow.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isTorchOn
                                ? AppTheme.discordYellow
                                : Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: _isTorchOn ? AppTheme.discordYellow : Colors.white,
                            size: 24,
                          ),
                        ),
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

/// Custom painter for the classroom sweep viewfinder, horizontal row alignment guide,
/// sweep direction arrows, and animated scanning line driven by device gyroscope and accelerometer.
class ClassroomSweepGuidelinePainter extends CustomPainter {
  final double panPosition; // 0.0 to 1.0 driven by gyroscope
  final double rollAngle; // radians (device roll tilt)
  final double pitchOffset; // pixels (elevation up/down)
  final double panVelocity; // rad/s (instantaneous yaw rate)
  final double animShimmer; // 0.0 to 1.0 (subtle breathing animation)
  final bool isRecording;
  final bool isMovingTooFast;
  final bool isLevel;

  ClassroomSweepGuidelinePainter({
    required this.panPosition,
    required this.rollAngle,
    required this.pitchOffset,
    required this.panVelocity,
    required this.animShimmer,
    required this.isRecording,
    required this.isMovingTooFast,
    required this.isLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = size.width * 0.88;
    final frameHeight = size.height * 0.44;
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2 - 30;
    final right = left + frameWidth;
    final bottom = top + frameHeight;
    final center = Offset(size.width / 2, top + frameHeight / 2);

    final primaryColor = isMovingTooFast
        ? AppTheme.discordRed
        : (isRecording ? const Color(0xFF57F287) : AppTheme.discordPurple);
    final accentColor = primaryColor.withValues(alpha: 0.85);

    // 1. Corner Brackets (length 28, stroke 3, rounded joins)
    final bracketPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bracketLen = 28.0;
    const r = 8.0;

    // Top-Left
    final tlPath = Path()
      ..moveTo(left, top + bracketLen)
      ..lineTo(left, top + r)
      ..quadraticBezierTo(left, top, left + r, top)
      ..lineTo(left + bracketLen, top);
    canvas.drawPath(tlPath, bracketPaint);

    // Top-Right
    final trPath = Path()
      ..moveTo(right - bracketLen, top)
      ..lineTo(right - r, top)
      ..quadraticBezierTo(right, top, right, top + r)
      ..lineTo(right, top + bracketLen);
    canvas.drawPath(trPath, bracketPaint);

    // Bottom-Left
    final blPath = Path()
      ..moveTo(left, bottom - bracketLen)
      ..lineTo(left, bottom - r)
      ..quadraticBezierTo(left, bottom, left + r, bottom)
      ..lineTo(left + bracketLen, bottom);
    canvas.drawPath(blPath, bracketPaint);

    // Bottom-Right
    final brPath = Path()
      ..moveTo(right - bracketLen, bottom)
      ..lineTo(right - r, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - r)
      ..lineTo(right, bottom - bracketLen);
    canvas.drawPath(brPath, bracketPaint);

    // 2. Gyroscope-Driven Leveled Horizon Guideline
    // Rotates with device roll & moves with pitch offset
    final centerY = center.dy + pitchOffset;
    canvas.save();
    canvas.translate(center.dx, centerY);
    // Tightly clamped tilt (max ±9 degrees) so line NEVER rotates sideways into landscape
    final visualTilt = rollAngle.clamp(-0.16, 0.16);
    canvas.rotate(-visualTilt);

    final horizonColor = isLevel
        ? const Color(0xFF57F287).withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.4);

    final horizonPaint = Paint()
      ..color = horizonColor
      ..strokeWidth = isLevel ? 1.8 : 1.2
      ..style = PaintingStyle.stroke;

    const dashWidth = 8.0;
    const dashSpace = 6.0;
    final halfW = frameWidth / 2 - 16;
    double curX = -halfW;
    while (curX < halfW) {
      final endX = min(curX + dashWidth, halfW);
      if (curX.abs() > 32) {
        canvas.drawLine(Offset(curX, 0), Offset(endX, 0), horizonPaint);
      }
      curX += dashWidth + dashSpace;
    }

    // Level indicator dots at ends of horizon line
    if (isLevel) {
      final dotPaint = Paint()
        ..color = const Color(0xFF57F287)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(-halfW + 6, 0), 3.5, dotPaint);
      canvas.drawCircle(Offset(halfW - 6, 0), 3.5, dotPaint);
    }

    // Center Crosshair Target
    final crosshairColor = isLevel ? const Color(0xFF57F287) : accentColor.withValues(alpha: 0.75);
    final crosshairPaint = Paint()
      ..color = crosshairColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset.zero, 6.0, crosshairPaint);
    canvas.drawLine(const Offset(-16, 0), const Offset(-8, 0), crosshairPaint);
    canvas.drawLine(const Offset(8, 0), const Offset(16, 0), crosshairPaint);
    canvas.drawLine(const Offset(0, -16), const Offset(0, -8), crosshairPaint);
    canvas.drawLine(const Offset(0, 8), const Offset(0, 16), crosshairPaint);

    if (isLevel) {
      final centerDotPaint = Paint()
        ..color = const Color(0xFF57F287)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, 2.2, centerDotPaint);
    }

    canvas.restore();

    // 3. Directional Sweep Chevrons (< and >)
    final isPanningLeft = panVelocity < -0.15;
    final isPanningRight = panVelocity > 0.15;

    final leftChevronPaint = Paint()
      ..color = isPanningLeft ? accentColor : Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = isPanningLeft ? 2.8 : 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final leftChevronX = left + 18.0;
    final lPath = Path()
      ..moveTo(leftChevronX + 6, centerY - 8)
      ..lineTo(leftChevronX, centerY)
      ..lineTo(leftChevronX + 6, centerY + 8);
    canvas.drawPath(lPath, leftChevronPaint);

    final rightChevronPaint = Paint()
      ..color = isPanningRight ? accentColor : Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = isPanningRight ? 2.8 : 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final rightChevronX = right - 18.0;
    final rPath = Path()
      ..moveTo(rightChevronX - 6, centerY - 8)
      ..lineTo(rightChevronX, centerY)
      ..lineTo(rightChevronX - 6, centerY + 8);
    canvas.drawPath(rPath, rightChevronPaint);

    // 4. Gyroscope-Driven Vertical Sweep Scanning Beam
    // Physical position across the screen corresponds directly to yaw rotation
    final scanX = left + frameWidth * panPosition;

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          accentColor.withValues(alpha: 0.35),
          accentColor.withValues(alpha: 0.9),
          accentColor.withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTRB(scanX - 1.5, top, scanX + 1.5, bottom))
      ..strokeWidth = 2.4;

    canvas.drawLine(Offset(scanX, top + 6), Offset(scanX, bottom - 6), beamPaint);

    // Motion trail glow in the direction of panning
    final trailOffset = (panVelocity * 16.0).clamp(-24.0, 24.0);
    final glowRect = Rect.fromLTRB(
      min(scanX, scanX - trailOffset) - 16,
      top + 10,
      max(scanX, scanX - trailOffset) + 16,
      bottom - 10,
    );
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.6,
        colors: [
          accentColor.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(glowRect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(glowRect, glowPaint);

    // Triangular indicator nibs at top and bottom of the scanning beam
    final nibPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    // Top nib (pointing downward)
    final topNib = Path()
      ..moveTo(scanX - 5, top)
      ..lineTo(scanX + 5, top)
      ..lineTo(scanX, top + 7)
      ..close();
    canvas.drawPath(topNib, nibPaint);

    // Bottom nib (pointing upward)
    final bottomNib = Path()
      ..moveTo(scanX - 5, bottom)
      ..lineTo(scanX + 5, bottom)
      ..lineTo(scanX, bottom - 7)
      ..close();
    canvas.drawPath(bottomNib, nibPaint);
  }

  @override
  bool shouldRepaint(covariant ClassroomSweepGuidelinePainter oldDelegate) {
    return oldDelegate.panPosition != panPosition ||
        oldDelegate.rollAngle != rollAngle ||
        oldDelegate.pitchOffset != pitchOffset ||
        oldDelegate.panVelocity != panVelocity ||
        oldDelegate.animShimmer != animShimmer ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.isMovingTooFast != isMovingTooFast ||
        oldDelegate.isLevel != isLevel;
  }
}
