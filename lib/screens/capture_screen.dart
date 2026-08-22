import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';

class CaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const CaptureScreen({super.key, required this.cameras});

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
      // Navigate to processing screen with file
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to: ${file.path}')),
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);

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
                  color: theme.colorScheme.error.withOpacity(0.3),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 64, color: Colors.white),
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
              ),
            ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (_isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isRecording ? theme.colorScheme.error : Colors.white,
                            width: 4,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: _isRecording ? 32 : 64,
                            height: _isRecording ? 32 : 64,
                            decoration: BoxDecoration(
                              color: _isRecording ? theme.colorScheme.error : Colors.white,
                              borderRadius: BorderRadius.circular(_isRecording ? 8 : 32),
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
