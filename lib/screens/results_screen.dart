import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/attendance_result.dart';
import '../models/attendance_session.dart';
import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/ambient_background.dart';
import 'capture_screen.dart';
import 'processing_screen.dart';

class ResultsScreen extends StatefulWidget {
  final AttendanceSession? session;
  final List<AttendanceResult>? initialResults;

  const ResultsScreen({
    super.key,
    this.session,
    this.initialResults,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // Track manual overrides (Student ID -> isPresent)
  final Map<String, bool> _overrides = {};
  String _searchQuery = '';
  late AttendanceSession? _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session != null) {
      _overrides.addAll(_session!.overrides);
    }
  }

  List<AttendanceResult> get _allResults => _session != null
      ? _session!.consolidatedResults
      : (widget.initialResults ?? []);

  AttendanceResult? get _debugEntry => _allResults
      .where((r) => r.studentId == '__pipeline_debug__')
      .firstOrNull;

  List<AttendanceResult> get _knownResults => _allResults
      .where((r) => r.studentId != '__pipeline_debug__')
      .toList();

  int get unknownGuestCount => _allResults
      .where((r) => r.status == AttendanceStatus.unknownGuest && r.studentId != '__pipeline_debug__')
      .length;

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

  void _toggleOverride(String key, bool currentIsPresent) async {
    setState(() {
      _overrides[key] = !currentIsPresent;
    });
    if (_session != null) {
      _session!.overrides[key] = !currentIsPresent;
      await ClassroomEngine.instance.saveActiveSession(_session!);
    }
  }

  Future<void> _exportCsv() async {
    try {
      File file;
      if (_session != null) {
        file = await ClassroomEngine.instance.exportSessionCsv(_session!);
      } else {
        final buffer = StringBuffer('Student ID,Name,Status,Similarity Score\n');
        for (final r in _knownResults) {
          final key = r.studentId ?? r.name ?? r.hashCode.toString();
          final isPresent = _overrides[key] ?? (r.status == AttendanceStatus.present);
          final status = isPresent ? 'present' : 'absent';
          buffer.writeln('${r.studentId ?? "N/A"},${r.name ?? "Unknown"},$status,${r.similarityScore.toStringAsFixed(4)}');
        }
        final dir = await getTemporaryDirectory();
        file = File(p.join(dir.path, 'attendance_${DateTime.now().millisecondsSinceEpoch}.csv'));
        await file.writeAsString(buffer.toString());
      }

      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: 'Consolidated attendance report');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmEndSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalize & Archive Session?'),
        content: Text(
          'This will finalize the attendance session for ${_session?.classId ?? "this class"} ($presentCount Present, $absentCount Absent across ${_session?.checkpoints.length ?? 1} sweep checkpoints). The session will be archived, allowing a fresh session to be started next class.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Active'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.discordPurple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalize Session'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ClassroomEngine.instance.finalizeActiveSession(_session?.classId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Class session finalized and archived successfully.'),
            backgroundColor: AppTheme.discordGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }

  List<AttendanceResult> _consolidatedResultsWithOverrides() {
    return _knownResults.map((r) {
      final key = r.studentId ?? r.name ?? r.hashCode.toString();
      final overridden = _overrides[key];
      if (overridden != null) {
        return r.copyWith(
          status: overridden ? AttendanceStatus.present : AttendanceStatus.absent,
        );
      }
      return r;
    }).toList();
  }

  Future<void> _showAddSweepSessionModal() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final checkpointNumber = (_session?.checkpoints.length ?? 0) + 1;
    final checkpointTitle = checkpointNumber == 2 ? 'Mid-Class Checkpoint' : 'Sweep Checkpoint #$checkpointNumber';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final size = media.size;

        return Container(
          decoration: BoxDecoration(
            color: (isDark ? AppTheme.darkSurface : AppTheme.lightSurface).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + media.padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Record $checkpointTitle',
                    style: TextStyle(
                      fontSize: (size.width * 0.045).clamp(16.0, 19.0),
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Currently $presentCount verified Present ($absentCount Absent). Sweep now to mark newly arrived or previously obscured students as Present without resetting existing records.',
                    style: TextStyle(
                      fontSize: (size.width * 0.031).clamp(12.0, 13.5),
                      color: secondaryTextColor,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Option 1: Live Sweep
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final cameras = await availableCameras();
                        if (cameras.isEmpty) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No camera available.')),
                            );
                          }
                          return;
                        }
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CaptureScreen(
                              cameras: cameras,
                              engine: ClassroomEngine.instance,
                              initialExistingResults: _consolidatedResultsWithOverrides(),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1F22) : const Color(0xFFF2F3F5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.discordPurple, AppTheme.discordDeepPurple],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Record Live Sweep Angle',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Scan students with real-time gyro guidelines',
                                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Option 2: Upload Video Clip
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          final picker = ImagePicker();
                          final picked = await picker.pickVideo(source: ImageSource.gallery);
                          if (picked != null && mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProcessingScreen(
                                  videoPath: picked.path,
                                  engine: ClassroomEngine.instance,
                                  initialExistingResults: _consolidatedResultsWithOverrides(),
                                  checkpointLabel: checkpointTitle,
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to load video: $e')),
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1F22) : const Color(0xFFF2F3F5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.discordGreen, Color(0xFF3BA55D)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.video_library_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Upload Sweep Video Clip',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Import video clip from device storage',
                                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: isDark ? Colors.white38 : Colors.black26,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
                            _session != null ? '${_session!.classId} Attendance Session' : 'Attendance Results',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _session != null
                                ? 'Session Active (${_session!.checkpoints.length} sweep${_session!.checkpoints.length > 1 ? "s" : ""}) • $presentCount/$totalCount Verified'
                                : '$totalCount Enrolled • $presentCount Verified',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_a_photo_rounded, color: AppTheme.discordPurple, size: 20),
                      tooltip: 'Take another sweep & aggregate',
                      onPressed: _showAddSweepSessionModal,
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded, color: AppTheme.discordPurple, size: 20),
                      tooltip: 'Export CSV at any time',
                      onPressed: _exportCsv,
                    ),
                    if (_session != null)
                      IconButton(
                        icon: const Icon(Icons.archive_outlined, color: AppTheme.discordLightPurple, size: 20),
                        tooltip: 'Finalize & End Class Session',
                        onPressed: _confirmEndSession,
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

              // Checkpoint History Timeline (Shows sweeps taken across the class)
              if (_session != null && _session!.checkpoints.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                  child: SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _session!.checkpoints.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        if (idx == _session!.checkpoints.length) {
                          // "+ Sweep Again" quick action chip
                          return ActionChip(
                            avatar: const Icon(Icons.add_a_photo_rounded, size: 14, color: AppTheme.discordPurple),
                            label: const Text('Sweep Again', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.discordPurple)),
                            backgroundColor: AppTheme.discordPurple.withValues(alpha: 0.12),
                            side: BorderSide(color: AppTheme.discordPurple.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            onPressed: _showAddSweepSessionModal,
                          );
                        }
                        final cp = _session!.checkpoints[idx];
                        final timeStr = "${cp.timestamp.hour.toString().padLeft(2, '0')}:${cp.timestamp.minute.toString().padLeft(2, '0')}";
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1F22) : const Color(0xFFF2F3F5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: AppTheme.discordGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${cp.index}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${cp.label} ($timeStr)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${cp.presentCount} present',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.discordGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

              if (absentCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.discordPurple.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.discordPurple.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, color: AppTheme.discordPurple, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$absentCount student${absentCount > 1 ? 's' : ''} not detected. Add a sweep angle to verify.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: primaryTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: _showAddSweepSessionModal,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.discordPurple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '+ Add Angle',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (unknownGuestCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$unknownGuestCount student face(s) detected in the room are not enrolled in this roster.',
                            style: TextStyle(fontSize: 12, color: primaryTextColor),
                          ),
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
                                  onTap: () => _toggleOverride(key, isPresent),
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

            // Bottom Action Bar: [Sweep Again (+)] and [Save Progress]
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Row(
                  children: [
                    // Button 1: Sweep Again (Take Next Sweep)
                    Expanded(
                      flex: 5,
                      child: OutlinedButton.icon(
                        onPressed: _showAddSweepSessionModal,
                        icon: const Icon(Icons.add_a_photo_rounded, size: 17),
                        label: const Text(
                          'Sweep Again',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                          minimumSize: const Size(0, 48),
                          side: BorderSide(
                            color: AppTheme.discordPurple.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Button 2: Save Progress & Return
                    Expanded(
                      flex: 6,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Session progress saved to device.'),
                              backgroundColor: AppTheme.discordGreen,
                              duration: Duration(seconds: 2),
                            ),
                          );
                          Navigator.pop(context, true);
                        },
                        icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                        label: const Text(
                          'Save Progress',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.discordPurple,
                          elevation: 3,
                          shadowColor: AppTheme.discordPurple.withValues(alpha: 0.4),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
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

