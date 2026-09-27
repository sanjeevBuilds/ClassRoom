import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../native/classroom_engine.dart';
import 'capture_screen.dart';
import 'enrollment_screen.dart';
import 'results_screen.dart' show BlurExtension;

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
    final newClass = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Add New Class', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Bio101',
            hintStyle: TextStyle(color: Colors.white54),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text('Select Classroom', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              if (classes.isEmpty)
                const Padding(padding: EdgeInsets.all(16.0), child: Text('No classes found', style: TextStyle(color: Colors.white54))),
              ...classes.map((c) => ListTile(
                title: Text(c, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                trailing: selectedClass == c ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: selectedClass == c ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => selectedClass = c);
                  ClassroomEngine.instance.switchClass(selectedClass);
                  _loadStudents();
                },
              )),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _addNewClass();
                },
                icon: const Icon(Icons.add),
                label: const Text('Create New Class'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
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
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
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
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
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

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Clear Roster?', style: TextStyle(color: Colors.white)),
        content: const Text('This will delete all enrolled students in this class.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ClassroomEngine.instance.clearRoster();
      await _loadStudents();
    }
  }

  Future<void> _exportCurrentRoster() async {
    if (enrolledStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No students in $selectedClass to export!')),
      );
      return;
    }
    try {
      final file = await ClassroomEngine.instance.exportClassroomRoster(selectedClass);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Classroom Roster: $selectedClass (${enrolledStudents.length} Students)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importRosterDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Import Classroom Roster', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the exported classroom JSON package to import all student profiles and face embeddings:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: '{"class_id": "CS101", "students": [...]}',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton.icon(
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
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          // Background glowing orbs
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.15),
              ),
            ).blurred(),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.15),
              ),
            ).blurred(),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Bar / Header
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _showClassSelector,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: primaryColor.withOpacity(0.2),
                                  child: Icon(Icons.class_, size: 14, color: primaryColor),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Active Classroom',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        selectedClass,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.5), size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
                        onPressed: _exportCurrentRoster,
                        tooltip: 'Export Classroom Roster',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_download_rounded, color: Colors.white70, size: 20),
                        onPressed: _importRosterDialog,
                        tooltip: 'Import Classroom Roster',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_sweep_rounded, color: theme.colorScheme.error.withOpacity(0.8)),
                        onPressed: _clearDatabase,
                        tooltip: 'Clear Database',
                        visualDensity: VisualDensity.compact,
                      ),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.surface,
                        child: const Icon(Icons.school, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Dashboard Stats Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Enrolled',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(Icons.people_alt_rounded, color: theme.colorScheme.secondary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isLoading ? '...' : '${enrolledStudents.length} Students',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions Grid (Fixed height)
                  SizedBox(
                    height: 120,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            context,
                            title: 'Take Attendance',
                            icon: Icons.camera_alt_rounded,
                            color: primaryColor,
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
                              if (!context.mounted) return;
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => CaptureScreen(cameras: cameras, engine: ClassroomEngine.instance),
                              ));
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildActionCard(
                            context,
                            title: 'Enroll Students',
                            icon: Icons.person_add_rounded,
                            color: theme.colorScheme.secondary,
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => EnrollmentScreen(engine: ClassroomEngine.instance),
                              ));
                              _loadStudents();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Enrolled List Header
                  Text(
                    'Enrolled Students',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Dynamic List View
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : enrolledStudents.isEmpty
                            ? Center(
                                child: Text(
                                  'No students enrolled in $selectedClass yet.',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 24),
                                itemCount: enrolledStudents.length,
                                itemBuilder: (context, index) {
                                  final s = enrolledStudents[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: primaryColor.withOpacity(0.2),
                                        child: Text(
                                          s['name'] != null ? s['name'].toString().substring(0, 1).toUpperCase() : '?',
                                          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text(
                                        s['name'] ?? 'Unknown',
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                      subtitle: Text(
                                        s['student_id'] ?? '',
                                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                        onPressed: () async {
                                          if (s['student_id'] != null) {
                                            await ClassroomEngine.instance.deleteStudent(s['student_id']);
                                            _loadStudents();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
