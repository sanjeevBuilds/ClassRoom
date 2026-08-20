import 'package:flutter/material.dart';

import '../modules/embedding_clustering/arcface_embedder.dart';
import '../modules/face_detection/yunet_detector.dart';
import '../modules/roster_matching/roster_db.dart';
import 'capture_screen.dart';
import 'enrollment_screen.dart';

/// Home screen — main navigation hub for the ClassRoom app.
///
/// Owns the shared, long-lived instances (roster DB, detector, embedder)
/// that both [CaptureScreen]'s pipeline and [EnrollmentScreen] need —
/// loading an ONNX model or opening the roster DB per-screen would be
/// wasteful and would lose enrolled students between navigations.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _rosterDb = RosterDB();
  final _detector = YuNetDetector();
  final _embedder = ArcFaceEmbedder();

  bool _isReady = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _rosterDb.init();
      await _detector.init('assets/models/yunet_int8.onnx');
      await _embedder.init('assets/models/arcface_mobilefacenet.onnx');
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
      if (mounted) setState(() => _initError = '$e');
    }
  }

  @override
  void dispose() {
    _rosterDb.close();
    _detector.dispose();
    _embedder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ClassRoom'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Automated Attendance',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'On-device • Offline • Private',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 48),
            if (_initError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Setup failed: $_initError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (!_isReady)
              const CircularProgressIndicator()
            else ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CaptureScreen(
                        rosterDb: _rosterDb,
                        detector: _detector,
                        embedder: _embedder,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Take Attendance'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EnrollmentScreen(
                        rosterDb: _rosterDb,
                        detector: _detector,
                        embedder: _embedder,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Enroll Students'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
