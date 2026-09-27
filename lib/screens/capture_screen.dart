import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initSensors();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    
    // Select back camera if available
    final camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _controller!.initialize();
    if (mounted) setState(() {});
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
          // Camera Preview
          CameraPreview(_controller!),

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
                    GlassCard(
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
                          Text(
                            _isRecording ? 'Sweeping Classroom…' : 'Sweep across classroom',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (_isRecording)
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        borderColor: AppTheme.discordRed.withValues(alpha: 0.5),
                        borderRadius: 14,
                        child: const Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: AppTheme.discordRed, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'REC',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isRecording ? AppTheme.discordRed : AppTheme.discordPurple,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isRecording ? AppTheme.discordRed : AppTheme.discordPurple).withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _isRecording ? 32 : 64,
                            height: _isRecording ? 32 : 64,
                            decoration: BoxDecoration(
                              color: _isRecording ? AppTheme.discordRed : AppTheme.discordPurple,
                              borderRadius: BorderRadius.circular(_isRecording ? 8 : 32),
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop_rounded : Icons.videocam_rounded,
                              color: Colors.white,
                              size: _isRecording ? 20 : 30,
                            ),
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

