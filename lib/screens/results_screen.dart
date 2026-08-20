import 'package:flutter/material.dart';
import '../models/attendance_result.dart';

/// Results screen — shows the attendance roll-call from a processed sweep.
///
/// Owner: Teammate 5 (Module 5)
class ResultsScreen extends StatelessWidget {
  final List<AttendanceResult> results;

  const ResultsScreen({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final debugEntry = results.where((r) => r.studentId == '__pipeline_debug__').firstOrNull;
    final displayResults = results.where((r) => r.studentId != '__pipeline_debug__').toList();

    final present = displayResults.where((r) => r.status == AttendanceStatus.present).toList();
    final absent = displayResults.where((r) => r.status == AttendanceStatus.absent).toList();
    final guests = displayResults.where((r) => r.status == AttendanceStatus.unknownGuest).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryRow(present: present.length, absent: absent.length, guests: guests.length),
          const SizedBox(height: 24),
          if (present.isNotEmpty) ...[
            Text('Present (${present.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ...present.map((r) => _ResultTile(result: r)),
            const SizedBox(height: 16),
          ],
          if (absent.isNotEmpty) ...[
            Text('Absent (${absent.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ...absent.map((r) => _ResultTile(result: r)),
            const SizedBox(height: 16),
          ],
          if (guests.isNotEmpty) ...[
            Text('Unrecognized / Guests (${guests.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ...guests.map((r) => _ResultTile(result: r)),
            const SizedBox(height: 16),
          ],
          if (debugEntry != null) ...[
            const Divider(),
            ExpansionTile(
              leading: const Icon(Icons.analytics_outlined, size: 20),
              title: const Text('Pipeline Telemetry', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    debugEntry.name ?? '',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int present, absent, guests;
  const _SummaryRow({required this.present, required this.absent, required this.guests});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SummaryChip(label: 'Present', count: present, color: Colors.green),
        _SummaryChip(label: 'Absent', count: absent, color: Colors.red),
        _SummaryChip(label: 'Guests', count: guests, color: Colors.orange),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        Text(label),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final AttendanceResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        switch (result.status) {
          AttendanceStatus.present => Icons.check_circle,
          AttendanceStatus.absent => Icons.cancel,
          AttendanceStatus.unknownGuest => Icons.person_search,
        },
        color: switch (result.status) {
          AttendanceStatus.present => Colors.green,
          AttendanceStatus.absent => Colors.red,
          AttendanceStatus.unknownGuest => Colors.orange,
        },
      ),
      title: Text(result.name ?? 'Unrecognized face'),
      subtitle: Text(
        result.status == AttendanceStatus.present
            ? 'Match Confidence: ${(result.similarityScore.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%'
            : 'Similarity: ${(result.similarityScore.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%',
      ),
    );
  }
}
