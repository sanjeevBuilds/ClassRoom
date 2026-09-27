import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/attendance_result.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ResultsScreen extends StatefulWidget {
  final List<AttendanceResult> initialResults;

  const ResultsScreen({super.key, required this.initialResults});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // Track manual overrides (Student ID -> isPresent)
  final Map<String, bool> _overrides = {};
  String _searchQuery = '';

  AttendanceResult? get _debugEntry => widget.initialResults
      .where((r) => r.studentId == '__pipeline_debug__')
      .firstOrNull;

  List<AttendanceResult> get _knownResults => widget.initialResults
      .where((r) => r.studentId != null && r.name != null && r.studentId != '__pipeline_debug__')
      .toList();

  List<AttendanceResult> get _filteredResults {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _knownResults;
    return _knownResults
        .where((r) =>
            r.name!.toLowerCase().contains(query) ||
            r.studentId!.toLowerCase().contains(query))
        .toList();
  }

  int get presentCount {
    int count = 0;
    for (var r in _knownResults) {
      bool isPresent = _overrides[r.studentId!] ?? (r.status == AttendanceStatus.present);
      if (isPresent) count++;
    }
    return count;
  }

  Future<void> _exportCsv() async {
    final buffer = StringBuffer('Student ID,Name,Status,Similarity Score\n');
    for (final r in _knownResults) {
      final isPresent = _overrides[r.studentId!] ?? (r.status == AttendanceStatus.present);
      final status = isPresent ? 'present' : 'absent';
      buffer.writeln('${r.studentId},${r.name},$status,${r.similarityScore.toStringAsFixed(4)}');
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'attendance_${DateTime.now().millisecondsSinceEpoch}.csv'));
    await file.writeAsString(buffer.toString());

    if (!mounted) return;
    await Share.shareXFiles([XFile(file.path)], text: 'Attendance results');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkScaffoldBg : AppTheme.lightScaffoldBg,
      appBar: AppBar(
        title: Text(
          'Attendance Results',
          style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.ios_share_rounded, color: AppTheme.discordPurple),
              tooltip: 'Export as CSV',
              onPressed: _exportCsv,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Ambient blurred glow orbs
          Positioned(
            top: -40,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.discordPurple.withValues(alpha: isDark ? 0.20 : 0.12),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -50,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.discordGreen.withValues(alpha: isDark ? 0.10 : 0.08),
                ),
              ),
            ),
          ),

          Column(
            children: [
              // Summary Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: GlassCard(
                  hasGlow: true,
                  glowColor: AppTheme.discordPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn('Present', presentCount.toString(), AppTheme.discordGreen, secondaryTextColor),
                      Container(
                        width: 1,
                        height: 44,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      _buildStatColumn('Absent', (_knownResults.length - presentCount).toString(), AppTheme.discordRed, secondaryTextColor),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'STUDENTS ATTENDANCE ROSTER',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Search Field in Glass Container
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: primaryTextColor),
                    decoration: InputDecoration(
                      hintText: 'Search students…',
                      hintStyle: TextStyle(color: secondaryTextColor),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.discordPurple),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Student List
              Expanded(
                child: _filteredResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No students enrolled in this class.'
                              : 'No students match "$_searchQuery".',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        itemCount: _filteredResults.length,
                        itemBuilder: (context, index) {
                          final result = _filteredResults[index];
                          final isPresent = _overrides[result.studentId!] ??
                              (result.status == AttendanceStatus.present);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: (isPresent ? AppTheme.discordGreen : AppTheme.discordPurple)
                                        .withValues(alpha: 0.18),
                                    child: Text(
                                      result.name!.isNotEmpty
                                          ? result.name!.substring(0, 1).toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: isPresent ? AppTheme.discordGreen : AppTheme.discordPurple,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          result.name!,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Text(
                                              result.studentId!,
                                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: (isPresent ? AppTheme.discordGreen : AppTheme.discordRed)
                                                    .withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isPresent ? 'PRESENT' : 'ABSENT',
                                                style: TextStyle(
                                                  color: isPresent ? AppTheme.discordGreen : AppTheme.discordRed,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isPresent,
                                    activeColor: AppTheme.discordPurple,
                                    activeTrackColor: AppTheme.discordPurple.withValues(alpha: 0.4),
                                    inactiveTrackColor: isDark ? Colors.white10 : Colors.black12,
                                    inactiveThumbColor: Colors.grey,
                                    onChanged: (value) {
                                      setState(() {
                                        _overrides[result.studentId!] = value;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              if (_debugEntry != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      collapsedIconColor: secondaryTextColor,
                      iconColor: AppTheme.discordPurple,
                      leading: Icon(Icons.analytics_outlined, size: 18, color: secondaryTextColor),
                      title: Text(
                        'Pipeline Telemetry',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor),
                      ),
                      children: [
                        GlassCard(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _debugEntry!.name ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Confirm & Save Button
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: const Text(
                      'Confirm & Save',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.discordPurple,
                      elevation: 4,
                      shadowColor: AppTheme.discordPurple.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  Widget _buildStatColumn(String label, String value, Color color, Color secondaryTextColor) {
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
            color: secondaryTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

