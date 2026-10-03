import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'capture_screen.dart';
import 'enrollment_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String selectedClass = 'CS101';
  List<String> classes = [];
  
  List<Map<String, dynamic>> enrolledStudents = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final loadedClasses = await ClassroomEngine.instance.getClasses();
    setState(() {
      classes = loadedClasses;
      if (!classes.contains(selectedClass)) {
        selectedClass = classes.first;
      }
    });
    _autoSelectClassBasedOnTime();
    await _loadStudents();
  }

  void _autoSelectClassBasedOnTime() {
    if (classes.isEmpty) return;
    final hour = DateTime.now().hour;
    if (hour < 10 && classes.contains('CS101')) selectedClass = 'CS101';
    else if (hour < 14 && classes.contains('Math202')) selectedClass = 'Math202';
    else if (classes.contains('Phy101')) selectedClass = 'Phy101';
    else selectedClass = classes.first;
    ClassroomEngine.instance.switchClass(selectedClass);
  }

  Future<void> _loadStudents() async {
    setState(() => isLoading = true);
    final students = await ClassroomEngine.instance.getEnrolledStudents();
    setState(() {
      enrolledStudents = students;
      isLoading = false;
    });
  }

  Future<void> _addNewClass() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final newClass = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Add New Class',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Bio101',
            hintStyle: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            filled: true,
            fillColor: AppTheme.discordPurple.withOpacity(0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppTheme.discordPurple.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.discordPurple, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.discordPurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) Navigator.pop(context, val);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (newClass != null && newClass.isNotEmpty) {
      await ClassroomEngine.instance.addClass(newClass);
      final loadedClasses = await ClassroomEngine.instance.getClasses();
      setState(() {
        classes = loadedClasses;
        selectedClass = newClass;
      });
      ClassroomEngine.instance.switchClass(selectedClass);
      await _loadStudents();
    }
  }

  void _showClassSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: (isDark ? AppTheme.darkSurface : AppTheme.lightSurface).withOpacity(0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : AppTheme.discordPurple.withOpacity(0.15),
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Classroom',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (classes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No classes found',
                    style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  ),
                ),
              ...classes.map((c) => ListTile(
                title: Text(
                  c,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: selectedClass == c
                    ? const Icon(Icons.check_circle_rounded, color: AppTheme.discordPurple)
                    : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: selectedClass == c ? AppTheme.discordPurple.withOpacity(0.12) : Colors.transparent,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => selectedClass = c);
                  ClassroomEngine.instance.switchClass(selectedClass);
                  _loadStudents();
                },
              )),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _addNewClass();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create New Class'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.discordPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _exportCurrentRoster();
                      },
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Export Roster', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        side: BorderSide(
                          color: isDark ? Colors.white.withOpacity(0.2) : AppTheme.discordPurple.withOpacity(0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _importRosterDialog();
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Import Roster', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        side: BorderSide(
                          color: isDark ? Colors.white.withOpacity(0.2) : AppTheme.discordPurple.withOpacity(0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportCurrentRoster() async {
    if (enrolledStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No students in this class to export! Enroll students first.')),
      );
      return;
    }
    try {
      final file = await ClassroomEngine.instance.exportClassroomRoster();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Classroom Roster Export: $selectedClass (${enrolledStudents.length} Students with 512-d Face Embeddings)',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${enrolledStudents.length} students from $selectedClass!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Entire Database?'),
        content: const Text(
          'This will delete ALL classes, enrolled students, face embeddings, and attendance records across the entire app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.discordRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ClassroomEngine.instance.clearAllData();
      await _initData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entire database cleared. Fresh start!')),
        );
      }
    }
  }

  Future<void> _importRosterDialog() async {
    final textController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Import Classroom Roster',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste the exported classroom JSON package to import all student profiles and face embeddings:',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: '{"class_id": "CS101", "students": [...]}',
                hintStyle: TextStyle(
                  color: isDark ? AppTheme.darkTextSecondary.withOpacity(0.5) : AppTheme.lightTextSecondary.withOpacity(0.5),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.discordPurple, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.discordPurple),
            icon: const Icon(Icons.file_download_done_rounded),
            label: const Text('Import'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (result == true && textController.text.trim().isNotEmpty) {
      try {
        final count = await ClassroomEngine.instance.importClassroomRoster(textController.text.trim());
        final updatedClasses = await ClassroomEngine.instance.getClasses();
        setState(() {
          classes = updatedClasses;
          selectedClass = ClassroomEngine.instance.currentClassId;
        });
        await _loadStudents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported $count students into $selectedClass!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background ambient glowing orbs (Discord Purple)
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.discordPurple.withOpacity(isDark ? 0.22 : 0.14),
              ),
            ).blurred(blur: 50),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.discordLightPurple.withOpacity(isDark ? 0.20 : 0.12),
              ),
            ).blurred(blur: 50),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Bar / Header
                  Row(
                    children: [
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          borderRadius: 20,
                          onTap: _showClassSelector,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.discordPurple.withValues(alpha: 0.18),
                                child: const Icon(Icons.class_rounded, size: 14, color: AppTheme.discordPurple),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Active Classroom',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      selectedClass,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Light / Dark Theme Switcher Button (Glass Card Pill)
                      GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(4),
                        child: IconButton(
                          icon: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: isDark ? AppTheme.discordYellow : AppTheme.discordPurple,
                            size: 22,
                          ),
                          onPressed: () {
                            appThemeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                          },
                          tooltip: isDark ? 'Switch to Light Glass' : 'Switch to Dark Glass',
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // More Options Menu in Glass Pill
                      GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(4),
                        child: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            size: 20,
                          ),
                          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onSelected: (value) {
                            if (value == 'export') _exportCurrentRoster();
                            if (value == 'import') _importRosterDialog();
                            if (value == 'clear') _clearDatabase();
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.share_rounded, size: 18, color: AppTheme.discordPurple),
                                  const SizedBox(width: 10),
                                  Text('Export Roster', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(Icons.file_download_rounded, size: 18, color: AppTheme.discordLightPurple),
                                  const SizedBox(width: 10),
                                  Text('Import Roster', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: const [
                                  Icon(Icons.delete_sweep_rounded, size: 18, color: AppTheme.discordRed),
                                  SizedBox(width: 10),
                                  Text('Clear Database', style: TextStyle(color: AppTheme.discordRed, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Dashboard Stats Card (Glassmorphism + Glow)
                  GlassCard(
                    hasGlow: true,
                    glowColor: AppTheme.discordPurple,
                    padding: const EdgeInsets.all(22),
                    borderRadius: 26,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Enrolled',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.discordPurple.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.people_alt_rounded,
                                color: AppTheme.discordPurple,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isLoading ? '...' : '${enrolledStudents.length} Students',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions Grid (Take Attendance & Enroll Students)
                  SizedBox(
                    height: 140,
                    child: Row(
                      children: [
                        Expanded(
                          child: GlassCard(
                            hasGlow: true,
                            glowColor: AppTheme.discordPurple,
                            borderRadius: 22,
                            padding: const EdgeInsets.all(12),
                            onTap: () async {
                              final cameras = await availableCameras();
                              if (cameras.isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('No camera found on this device.')),
                                  );
                                }
                                return;
                              }
                              if (!mounted) return;
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => CaptureScreen(cameras: cameras, engine: ClassroomEngine.instance),
                              ));
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [AppTheme.discordPurple, AppTheme.discordDeepPurple],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.discordPurple.withOpacity(0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 24, color: Colors.white),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Take Attendance',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: GlassCard(
                            hasGlow: true,
                            glowColor: AppTheme.discordDeepPurple,
                            borderRadius: 22,
                            padding: const EdgeInsets.all(12),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => EnrollmentScreen(engine: ClassroomEngine.instance),
                              ));
                              _loadStudents();
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [AppTheme.discordLightPurple, AppTheme.discordPurple],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.discordLightPurple.withOpacity(0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.person_add_rounded, size: 24, color: Colors.white),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Enroll Students',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Enrolled List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enrolled Students',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      if (enrolledStudents.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.discordPurple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${enrolledStudents.length} Active',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.discordPurple,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dynamic List View with GlassCards (Zero Overflow)
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator(color: AppTheme.discordPurple)),
                    )
                  else if (enrolledStudents.isEmpty)
                    GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      borderRadius: 18,
                      child: Center(
                        child: Text(
                          'No students enrolled in $selectedClass yet.\nTap "Enroll Students" to add.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: enrolledStudents.length,
                      itemBuilder: (context, index) {
                        final s = enrolledStudents[index];
                        final sName = s['name'] as String? ?? 'Unknown';
                        final sId = s['student_id'] as String? ?? '';
                        return GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          borderRadius: 18,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppTheme.discordPurple.withValues(alpha: 0.18),
                                child: Text(
                                  sName.isNotEmpty ? sName[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    color: AppTheme.discordPurple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.discordPurple.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Active Roster',
                                            style: TextStyle(
                                              color: AppTheme.discordPurple,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'ID: $sId',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: AppTheme.discordRed,
                                  size: 20,
                                ),
                                tooltip: 'Remove Student',
                                onPressed: () async {
                                  if (s['student_id'] != null) {
                                    await ClassroomEngine.instance.deleteStudent(s['student_id']);
                                    _loadStudents();
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
