import 'package:flutter/material.dart';

/// Home screen — main navigation hub for the ClassRoom app.
///
/// Provides access to:
/// - Capture: Record a new classroom sweep video
/// - Enrollment: Add/manage students in the roster
/// - History: View past attendance records
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassRoom'),
        centerTitle: true,
      ),
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
            // TODO: Add navigation buttons to Capture, Enrollment, History screens
            FilledButton.icon(
              onPressed: () {
                // TODO: Navigate to CaptureScreen
              },
              icon: const Icon(Icons.videocam_rounded),
              label: const Text('Take Attendance'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Navigate to EnrollmentScreen
              },
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Enroll Students'),
            ),
          ],
        ),
      ),
    );
  }
}
