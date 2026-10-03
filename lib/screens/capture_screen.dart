import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
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

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  StreamSubscription? _gyroSubscription;
  bool _isMovingTooFast = false;
  bool _isRecording = false;
  bool _isTorchOn = false;
  bool _isPickingVideo = false;

  @override
  void initState() {
    super.initState();
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
      // Calculate angular velocity magnitude
      final speed = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      // Threshold in rad/s (approx 85 degrees per second)
      final tooFast = speed > 1.5;

      if (tooFast != _isMovingTooFast) {
        setState(() {
          _isMovingTooFast = tooFast;
        });
      }
    });
  }

  @override
  void dispose() {
    _gyroSubscription?.cancel();
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
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
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
