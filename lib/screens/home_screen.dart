import 'package:flutter/material.dart';

import '../native/classroom_engine.dart';
import 'capture_screen.dart';
import 'enrollment_screen.dart';

/// Home screen — main navigation hub for the ClassRoom app.
///
/// Owns the single, long-lived [ClassroomEngine] instance (extracted model
/// paths + roster DB path) that both [CaptureScreen] and [EnrollmentScreen]
/// need — re-extracting the .onnx assets per-screen would be wasteful.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ClassroomEngine? _engine;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final engine = await ClassroomEngine.init();
      if (mounted) setState(() => _engine = engine);
    } catch (e) {
      if (mounted) setState(() => _initError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
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
            else if (engine == null)
              const CircularProgressIndicator()
            else ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CaptureScreen(engine: engine),
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
                      builder: (_) => EnrollmentScreen(engine: engine),
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
