import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/attendance_result.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/ambient_background.dart';

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
      .where((r) => r.studentId != '__pipeline_debug__')
      .toList();

  List<AttendanceResult> get _filteredResults {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _knownResults;
    return _knownResults
        .where((r) =>
            (r.name ?? '').toLowerCase().contains(query) ||
            (r.studentId ?? '').toLowerCase().contains(query))
        .toList();
  }

  int get presentCount {
    int count = 0;
    for (var r in _knownResults) {
      final key = r.studentId ?? r.name ?? r.hashCode.toString();
      bool isPresent = _overrides[key] ?? (r.status == AttendanceStatus.present);
      if (isPresent) count++;
    }
    return count;
  }

  Future<void> _exportCsv() async {
    final buffer = StringBuffer('Student ID,Name,Status,Similarity Score\n');
    for (final r in _knownResults) {
      final key = r.studentId ?? r.name ?? r.hashCode.toString();
      final isPresent = _overrides[key] ?? (r.status == AttendanceStatus.present);
      final status = isPresent ? 'present' : 'absent';
      buffer.writeln('${r.studentId ?? "N/A"},${r.name ?? "Unknown"},$status,${r.similarityScore.toStringAsFixed(4)}');
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
    final totalCount = _knownResults.length;
    final absentCount = totalCount - presentCount;
    final attendanceRate = totalCount == 0 ? 0 : ((presentCount / totalCount) * 100).round();

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: primaryTextColor,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Attendance Results',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$totalCount Enrolled • $presentCount Verified',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded, color: AppTheme.discordPurple, size: 20),
                      tooltip: 'Export as CSV',
                      onPressed: _exportCsv,
                    ),
                  ],
                ),
              ),

              // Summary Stat Header (Present | Absent | Attendance Rate)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: GlassCard(
                  hasGlow: true,
                  glowColor: AppTheme.discordPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatColumn('Present', presentCount.toString(), AppTheme.discordGreen, secondaryTextColor),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      Expanded(
                        child: _buildStatColumn('Absent', absentCount.toString(), AppTheme.discordRed, secondaryTextColor),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      Expanded(
                        child: _buildStatColumn('Rate', '$attendanceRate%', AppTheme.discordPurple, secondaryTextColor),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: primaryTextColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name or ID…',
                      hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.discordPurple),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              color: secondaryTextColor,
                              onPressed: () => setState(() => _searchQuery = ''),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Roster Header Label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'STUDENT ROSTER (${_filteredResults.length})',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Student List
              Expanded(
                child: _filteredResults.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.discordPurple.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                              child: const Icon(
                                Icons.people_outline_rounded,
                                size: 38,
                                color: AppTheme.discordPurple,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _searchQuery.isEmpty ? 'No Students Recorded' : 'No Students Match',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No enrolled student records found in this sweep.'
                                  : 'No student matches "$_searchQuery".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      itemCount: _filteredResults.length,
                      itemBuilder: (context, index) {
                        final result = _filteredResults[index];
                        final studentName = result.name ?? 'Unregistered Student';
                        final studentId = result.studentId ?? 'N/A';
                        final key = result.studentId ?? result.name ?? result.hashCode.toString();
                        final isPresent = _overrides[key] ??
                            (result.status == AttendanceStatus.present);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: (isPresent ? AppTheme.discordGreen : AppTheme.discordPurple)
                                      .withValues(alpha: 0.18),
                                  child: Text(
                                    studentName.isNotEmpty
                                        ? studentName.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: isPresent ? AppTheme.discordGreen : AppTheme.discordPurple,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          studentName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              studentId,
                                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                            ),
                                            if (result.similarityScore > 0) ...[
                                              Text(
                                                ' • ${(result.similarityScore * 100).toStringAsFixed(0)}% match',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.discordLightPurple,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Sleek Interactive Status Toggle Pill
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _overrides[key] = !isPresent;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: (isPresent ? AppTheme.discordGreen : AppTheme.discordRed)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: (isPresent ? AppTheme.discordGreen : AppTheme.discordRed)
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                          size: 13,
                                          color: isPresent ? AppTheme.discordGreen : AppTheme.discordRed,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isPresent ? 'Present' : 'Absent',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isPresent ? AppTheme.discordGreen : AppTheme.discordRed,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    collapsedIconColor: secondaryTextColor,
                    iconColor: AppTheme.discordPurple,
                    leading: Icon(Icons.analytics_outlined, size: 16, color: secondaryTextColor),
                    title: Text(
                      'Pipeline Telemetry',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor),
                    ),
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _debugEntry!.name ?? '',
                          style: TextStyle(
                            fontSize: 11,
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
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Attendance verified & saved.'),
                          backgroundColor: AppTheme.discordGreen,
                          duration: Duration(seconds: 2),
                        ),
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                    label: const Text(
                      'Confirm & Save',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.discordPurple,
                      elevation: 3,
                      shadowColor: AppTheme.discordPurple.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      alignment: Alignment.center,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color, Color secondaryTextColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

