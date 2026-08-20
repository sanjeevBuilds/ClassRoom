import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../native/classroom_engine.dart';
import 'processing_screen.dart';

/// Capture screen — records a single handheld classroom sweep video.
///
/// Owner: Teammate 1 (Module 1)
///
/// Records via the phone's own camera (no separate app, no laptop), then
/// hands the saved video off to [ProcessingScreen] to run the full pipeline.
class CaptureScreen extends StatefulWidget {
  final ClassroomEngine engine;

  const CaptureScreen({super.key, required this.engine});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isTogglingRecording = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _errorMessage = 'Camera permission is required to record a sweep.');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _errorMessage = 'No camera found on this device.');
      return;
    }

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.high, // 1080p, per the interface contract's input spec
      enableAudio: false, // attendance capture doesn't need audio
    );

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Could not start camera: $e');
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // Guard against a second tap landing while the first start/stop call is
    // still in flight — startVideoRecording()/stopVideoRecording() are both
    // async, and _isRecording only flips *after* they resolve, so without
    // this a fast double-tap calls startVideoRecording() twice and throws
    // CameraException("Video is already recording").
    if (_isTogglingRecording) return;
    _isTogglingRecording = true;

    try {
      if (_isRecording) {
        final file = await controller.stopVideoRecording();
        setState(() => _isRecording = false);
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(
              videoPath: file.path,
              engine: widget.engine,
            ),
          ),
        );
      } else {
        await controller.startVideoRecording();
        setState(() => _isRecording = true);
      }
    } finally {
      _isTogglingRecording = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Sweep')),
      body: _buildBody(),
      floatingActionButton: _controller != null && _controller!.value.isInitialized
          ? FloatingActionButton.large(
              onPressed: _toggleRecording,
              backgroundColor: _isRecording ? Colors.red : null,
              child: Icon(_isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return CameraPreview(controller);
  }
}
