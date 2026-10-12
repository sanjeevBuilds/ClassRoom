import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../native/classroom_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_card.dart';
import 'processing_screen.dart';

class BenchmarkValidationScreen extends StatefulWidget {
  final ClassroomEngine engine;

  const BenchmarkValidationScreen({super.key, required this.engine});

  @override
  State<BenchmarkValidationScreen> createState() => _BenchmarkValidationScreenState();
}

class _BenchmarkValidationScreenState extends State<BenchmarkValidationScreen> {
  int _selectedScenarioIndex = 0; // Default to Scenario 1 (Standard Tiered Hall)
  bool _isPickingVideo = false;

  String _detectorDisplayName(String key) {
    switch (key.toLowerCase()) {
      case 'yunet':
        return 'YuNet INT8';
      case 'retinaface':
        return 'RetinaFace';
      case 'haar':
        return 'Haar Cascade';
      default:
        return key.toUpperCase();
    }
  }

  final List<Map<String, dynamic>> _scenarios = [
    {
      'id': 'S1',
      'shortName': 'Tiered Hall',
      'name': 'Scenario 1: Standard Tiered Hall',
      'students': 40,
      'lux': 152,
      'depth': 'Rows 1-6 (1-4m)',
      'desc': 'Standard tiered lecture hall with uniform ambient illumination and elevated row seating.',
      'ref_f1': '99.5%',
      'ref_time': '9.15s',
      'yunet_f1': '98.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '97.2%',
      'far': '1.6%',
    },
    {
      'id': 'S2',
      'shortName': 'High Density',
      'name': 'Scenario 2: High-Density Seating',
      'students': 38,
      'lux': 152,
      'depth': 'Rows 1-6 (1-5m)',
      'desc': 'High-occupancy amphitheater setting featuring inter-student occlusions and compact seating pitch.',
      'ref_f1': '99.5%',
      'ref_time': '12.7s',
      'yunet_f1': '98.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '97.2%',
      'far': '1.6%',
    },
    {
      'id': 'S3',
      'shortName': 'Seminar Room',
      'name': 'Scenario 3: Interactive Seminar Room',
      'students': 32,
      'lux': 152,
      'depth': 'Rows 1-5 (1-4m)',
      'desc': 'Seminar room layout with angular seating profiles and desk workspace occlusions.',
      'ref_f1': '99.5%',
      'ref_time': '9.66s',
      'yunet_f1': '98.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '97.2%',
      'far': '1.6%',
    },
    {
      'id': 'S4',
      'shortName': 'Low Light',
      'name': 'Scenario 4: Dim Ambient Projection',
      'students': 32,
      'lux': 40,
      'depth': 'Rows 1-5 (1-5m)',
      'desc': 'Low-lux lecture environment (40 Lux) under active multimedia presentation display.',
      'ref_f1': '100%',
      'ref_time': '11.5s',
      'yunet_f1': '97.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '96.5%',
      'far': '2.5%',
    },
    {
      'id': 'S5',
      'shortName': 'Deep Hall',
      'name': 'Scenario 5: Extended Depth Auditorium',
      'students': 60,
      'lux': 140,
      'depth': 'Rows 1-10 (1-8m)',
      'desc': 'Deep amphitheater configuration with extended subject distances up to 8 meters.',
      'ref_f1': '94.8%',
      'ref_time': '4.18s',
      'yunet_f1': '97.4%',
      'yunet_time': '22.4 ms',
      'rear_recall': '94.4%',
      'far': '3.3%',
    },
  ];

  Future<void> _pickAndRunSweepVideo() async {
    if (_isPickingVideo) return;
    setState(() => _isPickingVideo = true);

    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video == null || !mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProcessingScreen(
            videoPath: video.path,
            engine: widget.engine,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting video: $e'), backgroundColor: AppTheme.discordRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingVideo = false);
    }
  }

  void _showDetectorPickerModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2B2D31) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              )
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Face Detection Engine',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 6),
                Text(
                  'Switch between detectors live for comparative latency and multi-row recall evaluation.',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(height: 16),
                _buildDetectorOption(
                  key: 'yunet',
                  title: 'YuNet INT8 + SAHI',
                  subtitle: '11.8ms per frame • Quantized 100KB • 2.5x Rear Horizon Zoom • Edge Optimized',
                  badge: 'RECOMMENDED',
                  badgeColor: AppTheme.discordGreen,
                  isSelected: widget.engine.activeDetector == 'yunet',
                  onTap: () {
                    setState(() => widget.engine.setActiveDetector('yunet'));
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 10),
                _buildDetectorOption(
                  key: 'retinaface',
                  title: 'RetinaFace MobileNet-0.25',
                  subtitle: '52.3ms CPU (9.1s GPU) • ResNet FPN • High Accuracy Deep Detector',
                  badge: '',
                  badgeColor: AppTheme.discordPurple,
                  isSelected: widget.engine.activeDetector == 'retinaface',
                  onTap: () {
                    setState(() => widget.engine.setActiveDetector('retinaface'));
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 10),
                _buildDetectorOption(
                  key: 'haar',
                  title: 'Haar Cascade (OpenCV)',
                  subtitle: '68.2ms • CPU XML Classifier • Classical Viola-Jones',
                  badge: '',
                  badgeColor: Colors.amber,
                  isSelected: widget.engine.activeDetector == 'haar',
                  onTap: () {
                    setState(() => widget.engine.setActiveDetector('haar'));
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectorOption({
    required String key,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.discordPurple.withValues(alpha: 0.12)
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.discordPurple : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? AppTheme.discordPurple : (isDark ? Colors.white30 : Colors.black26),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.discordPurple : primaryTextColor,
                        ),
                      ),
                      if (badge.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54, height: 1.25),
                  ),
                ],
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
    final currentScenario = _scenarios[_selectedScenarioIndex];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: primaryTextColor,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Benchmark Evaluation',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                                color: primaryTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Edge CPU vs Cloud Baseline',
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Active Detector Switcher Button
                    InkWell(
                      onTap: _showDetectorPickerModal,
                      borderRadius: BorderRadius.circular(17),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.discordBlurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: AppTheme.discordBlurple.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.tune_rounded, size: 13, color: AppTheme.discordBlurple),
                            const SizedBox(width: 5),
                            Text(
                              _detectorDisplayName(widget.engine.activeDetector),
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.discordBlurple,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.discordBlurple),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Pinned Scenario Selector Carousel
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  height: 34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _scenarios.length,
                    itemBuilder: (ctx, idx) {
                      final sc = _scenarios[idx];
                      final isSelected = idx == _selectedScenarioIndex;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => setState(() => _selectedScenarioIndex = idx),
                          borderRadius: BorderRadius.circular(17),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.discordBlurple
                                  : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.discordBlurple
                                    : (isDark ? Colors.white12 : Colors.black12),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Text(
                              sc['shortName'] as String,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.1,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected ? Colors.white : primaryTextColor,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  children: [
                    // Active Scenario Card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.discordBlurple.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.meeting_room_rounded, size: 13, color: AppTheme.discordBlurple),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${currentScenario['id']} • ${currentScenario['students']} Students',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.discordBlurple),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              currentScenario['name'],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              currentScenario['desc'],
                              style: TextStyle(fontSize: 12, color: secondaryTextColor, height: 1.3),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _buildMetricMini(
                                  label: 'Illuminance',
                                  value: '${currentScenario['lux']} Lux',
                                  icon: Icons.lightbulb_outline_rounded,
                                  color: currentScenario['lux'] < 50 ? Colors.amber : Colors.blue,
                                ),
                                const SizedBox(width: 12),
                                _buildMetricMini(
                                  label: 'Hall Depth',
                                  value: currentScenario['depth'],
                                  icon: Icons.straighten_rounded,
                                  color: AppTheme.discordBlurple,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Empirical Benchmark Metrics Card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.compare_arrows_rounded, color: AppTheme.discordPurple, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Empirical Benchmark Metrics',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            // Metrics Grid
                            Row(
                              children: [
                                Expanded(
                                  child: _buildComparisonTile(
                                    title: 'F1-Score',
                                    ourValue: currentScenario['yunet_f1'],
                                    referenceLabel: 'Reference',
                                    referenceValue: currentScenario['ref_f1'],
                                    isPositive: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildComparisonTile(
                                    title: 'Inference Latency',
                                    ourValue: currentScenario['yunet_time'],
                                    referenceLabel: 'Cloud GPU',
                                    referenceValue: currentScenario['ref_time'],
                                    isPositive: true,
                                    isSpeed: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildComparisonTile(
                                    title: 'Rear-Row Recall (6-8m)',
                                    ourValue: currentScenario['rear_recall'],
                                    referenceLabel: 'Without Zoom',
                                    referenceValue: '72.2%',
                                    isPositive: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildComparisonTile(
                                    title: 'False Absence Rate',
                                    ourValue: currentScenario['far'],
                                    referenceLabel: 'Raw Baseline',
                                    referenceValue: '27.8%',
                                    isPositive: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Action Button: Run on Video File
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isPickingVideo ? null : _pickAndRunSweepVideo,
                        icon: _isPickingVideo
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.video_library_rounded),
                        label: Text(_isPickingVideo ? 'Analyzing Video...' : 'Run Video Benchmark'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.discordPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricMini({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonTile({
    required String title,
    required String ourValue,
    required String referenceLabel,
    required String referenceValue,
    required bool isPositive,
    bool isSpeed = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                ourValue,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.discordGreen),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_upward_rounded, size: 13, color: AppTheme.discordGreen),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$referenceLabel: $referenceValue',
              style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}
