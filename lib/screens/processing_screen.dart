import 'package:flutter/material.dart';

import '../native/classroom_engine.dart';
import 'results_screen.dart';

/// Processing screen — hands the recorded sweep video to the C++ engine
/// (native/src/pipeline.cpp), which runs the entire sample -> blur filter
/// -> detect -> embed -> cluster -> match sequence natively in one call,
/// then navigates to [ResultsScreen] with the parsed JSON result.
class ProcessingScreen extends StatefulWidget {
  final String videoPath;
  final ClassroomEngine engine;

  const ProcessingScreen({
    super.key,
    required this.videoPath,
    required this.engine,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final results = await widget.engine.processSweepVideo(widget.videoPath);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultsScreen(initialResults: results)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Processing failed: $_error', textAlign: TextAlign.center),
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing sweep…'),
                ],
              ),
      ),
    );
  }
}
