import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/attendance_result.dart';

class ResultsScreen extends StatefulWidget {
  final List<AttendanceResult> initialResults;

  const ResultsScreen({super.key, required this.initialResults});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // Track manual overrides (Student ID -> isPresent)
  final Map<String, bool> _overrides = {};

  int get presentCount {
    int count = 0;
    for (var r in widget.initialResults) {
      if (r.studentId == null) continue;
      bool isPresent = _overrides[r.studentId!] ?? (r.status == AttendanceStatus.present);
      if (isPresent) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Attendance Results'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.15),
              ),
            ).blurred(),
          ),
          
          Column(
            children: [
              // Summary Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn('Present', presentCount.toString(), primaryColor),
                      Container(width: 1, height: 40, color: Colors.white.withOpacity(0.2)),
                      _buildStatColumn('Absent', (results.length - presentCount).toString(), theme.colorScheme.error),
                    ],
                  ),
                ),
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Manual Overrides',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Student List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: widget.initialResults.length,
                  itemBuilder: (context, index) {
                    final result = widget.initialResults[index];
                    if (result.studentId == null || result.name == null) return const SizedBox.shrink();
                    
                    final isPresent = _overrides[result.studentId!] ?? (result.status == AttendanceStatus.present);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: primaryColor.withOpacity(0.2),
                          child: Text(
                            result.name!.substring(0, 1).toUpperCase(),
                            style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          result.name!,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        subtitle: Text(
                          result.studentId!,
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        trailing: Switch(
                          value: isPresent,
                          activeColor: primaryColor,
                          inactiveTrackColor: theme.colorScheme.surface,
                          inactiveThumbColor: Colors.grey,
                          onChanged: (value) {
                            setState(() {
                              _overrides[result.studentId!] = value;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Export Button
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Navigate back or Export to CSV
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirm & Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

extension BlurExtension on Widget {
  Widget blurred({double sigma = 40.0}) {
    return ImageFilterWidget(sigma: sigma, child: this);
  }
}

class ImageFilterWidget extends StatelessWidget {
  final Widget child;
  final double sigma;
  const ImageFilterWidget({super.key, required this.child, required this.sigma});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
