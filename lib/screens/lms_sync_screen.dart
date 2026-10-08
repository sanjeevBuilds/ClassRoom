import 'package:flutter/material.dart';
import '../services/lms_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class LmsSyncScreen extends StatefulWidget {
  final List<AttendanceSyncRecord> records;
  final String classLabel;

  const LmsSyncScreen({super.key, required this.records, required this.classLabel});

  @override
  State<LmsSyncScreen> createState() => _LmsSyncScreenState();
}

class _LmsSyncScreenState extends State<LmsSyncScreen> {
  LmsPortalType? _selectedPortal;
  bool _isSyncing = false;
  SyncResult? _syncResult;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _courseController = TextEditingController();
  final TextEditingController _instructorController = TextEditingController();

  final String _sessionLabel = "${DateTime.now().day.toString().padLeft(2, '0')} ${_monthString(DateTime.now().month)} ${DateTime.now().year}, ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";

  static String _monthString(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _courseController.dispose();
    _instructorController.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_selectedPortal == null) return;
    
    setState(() {
      _isSyncing = true;
      _syncResult = null;
    });

    final service = LmsSyncService();
    LmsSyncConfig config;

    switch (_selectedPortal!) {
      case LmsPortalType.psgECampus:
        config = LmsSyncService.psgECampusConfig(
          baseUrl: _urlController.text,
          token: _tokenController.text,
          courseId: _courseController.text,
          instructorId: _instructorController.text,
        );
        break;
      case LmsPortalType.googleClassroom:
        config = LmsSyncService.googleClassroomConfig(
          token: _tokenController.text,
          courseId: _courseController.text,
          instructorId: _instructorController.text,
        );
        break;
      case LmsPortalType.canvasLms:
        config = LmsSyncService.canvasConfig(
          baseUrl: _urlController.text,
          token: _tokenController.text,
          courseId: _courseController.text,
          instructorId: _instructorController.text,
        );
        break;
    }

    final result = await service.syncAttendance(
      config: config,
      records: widget.records,
      sessionLabel: widget.classLabel + " - " + _sessionLabel,
    );

    setState(() {
      _isSyncing = false;
      _syncResult = result;
    });
  }

  Widget _buildPortalCard(LmsPortalType type, String name, IconData icon) {
    final isSelected = _selectedPortal == type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GlassCard(
        onTap: () {
          setState(() {
            _selectedPortal = type;
            _syncResult = null;
          });
        },
        hasGlow: isSelected,
        glowColor: AppTheme.discordPurple,
        borderColor: isSelected ? AppTheme.discordPurple : null,
        borderWidth: isSelected ? 2.0 : 1.2,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 32, color: isSelected ? AppTheme.discordPurple : (isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    final needsUrl = _selectedPortal == LmsPortalType.psgECampus || _selectedPortal == LmsPortalType.canvasLms;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sync to LMS', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
      ),
      body: Stack(
        children: [
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
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Push attendance to your institution portal',
                style: TextStyle(fontSize: 16, color: secondaryTextColor),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _buildPortalCard(LmsPortalType.psgECampus, 'PSG e-Campus', Icons.account_balance),
                  const SizedBox(width: 12),
                  _buildPortalCard(LmsPortalType.googleClassroom, 'Google Classroom', Icons.school),
                  const SizedBox(width: 12),
                  _buildPortalCard(LmsPortalType.canvasLms, 'Canvas', Icons.book),
                ],
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _selectedPortal == null
                    ? const SizedBox.shrink()
                    : Column(
                        key: ValueKey(_selectedPortal),
                        children: [
                          if (needsUrl) ...[
                            _buildTextField('Server URL', _urlController, Icons.link),
                            const SizedBox(height: 16),
                          ],
                          _buildTextField('Course ID', _courseController, Icons.class_),
                          const SizedBox(height: 16),
                          _buildTextField('Instructor ID', _instructorController, Icons.person),
                          const SizedBox(height: 16),
                          _buildTextField('Bearer Token', _tokenController, Icons.vpn_key, obscureText: true),
                          const SizedBox(height: 16),
                          GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, color: AppTheme.discordPurple),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Session Label', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                                      Text(widget.classLabel + " - " + _sessionLabel, style: TextStyle(fontSize: 14, color: primaryTextColor)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _isSyncing ? null : _sync,
                              child: _isSyncing
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Sync Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              if (_syncResult != null)
                GlassCard(
                  hasGlow: true,
                  glowColor: _syncResult!.success ? AppTheme.discordGreen : AppTheme.discordRed,
                  borderColor: _syncResult!.success ? AppTheme.discordGreen : AppTheme.discordRed,
                  child: Row(
                    children: [
                      Icon(
                        _syncResult!.success ? Icons.check_circle : Icons.error,
                        color: _syncResult!.success ? AppTheme.discordGreen : AppTheme.discordRed,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _syncResult!.success ? 'Success' : 'Failed',
                              style: TextStyle(
                                color: _syncResult!.success ? AppTheme.discordGreen : AppTheme.discordRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _syncResult!.message,
                              style: TextStyle(color: primaryTextColor),
                            ),
                            if (_syncResult!.errorCode != null)
                              Text(
                                'Error code: ${_syncResult!.errorCode}',
                                style: TextStyle(color: secondaryTextColor, fontSize: 12),
                              ),
                            if (_syncResult!.success)
                              Text(
                                'Students submitted: ${_syncResult!.studentsSubmitted}',
                                style: TextStyle(color: secondaryTextColor, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool obscureText = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
          prefixIcon: Icon(icon, color: AppTheme.discordPurple),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
