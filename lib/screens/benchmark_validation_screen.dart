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
  int _selectedScenarioIndex = 4; // Default to Scenario 5 (Deep Tiered Hall)
  bool _isPickingVideo = false;

  final List<Map<String, dynamic>> _scenarios = [
    {
      'id': 'S1',
      'name': 'Scenario 1: Standard Tiered Hall',
      'students': 40,
      'lux': 152,
      'depth': 'Rows 1-6 (1-4m)',
      'desc': 'Standard lecture hall with uniform fluorescent illumination.',
      'paper1_f1': '99.5% (RetinaFace GPU)',
      'paper1_time': '9.15s (T4 GPU)',
      'yunet_f1': '98.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '97.2%',
      'far': '1.6%',
    },
    {
      'id': 'S2',
      'name': 'Scenario 2: High-Density Tiered Hall',
      'students': 38,
      'lux': 152,
      'depth': 'Rows 1-6 (1-5m)',
      'desc': 'Tight bench spacing with frequent shoulder and head occlusions.',
      'paper1_f1': '99.5% (RetinaFace GPU)',
      'paper1_time': '12.73s (T4 GPU)',
      'yunet_f1': '98.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '97.2%',
      'far': '1.6%',
    },
    {
      'id': 'S3',
      'name': 'Scenario 3: Medium Seminar Room',
      'students': 32,
      'lux': 152,
      'depth': 'Rows 1-5 (1-4m)',
      'desc': 'Angled student postures, note-taking and laptops on desks.',
      'paper1_f1': '99.5% (RetinaFace GPU)',
      'paper1_time': '9.66s (T4 GPU)',
      'yunet_f1': '98.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '97.2%',
      'far': '1.6%',
    },
    {
      'id': 'S4',
      'name': 'Scenario 4: Dim-Light Projector Lecture',
      'students': 32,
      'lux': 40,
      'depth': 'Rows 1-5 (1-5m)',
      'desc': '40 Lux low-light projection mode. Haar Cascade collapses to 25% recall.',
      'paper1_f1': '100% (RetinaFace GPU)',
      'paper1_time': '11.47s (T4 GPU)',
      'yunet_f1': '97.3%',
      'yunet_time': '22.4 ms',
      'rear_recall': '96.5%',
      'far': '2.5%',
    },
    {
      'id': 'S5',
      'name': 'Scenario 5: PSG Tech Deep Tiered Hall',
      'students': 60,
      'lux': 140,
      'depth': 'Rows 1-10 (1-8m Depth)',
      'desc': 'Challenging 10-row amphitheater with rear rows 6-10 at 6-8 meters.',
      'paper1_f1': '94.8% (RetinaFace GPU)',
      'paper1_time': '4.18s (GPU)',
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                badge: 'PROPOSED',
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
                subtitle: '52.3ms CPU (9.1s GPU) • ResNet FPN • Base Paper 1 Accuracy Baseline',
                badge: 'BASE PAPER',
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
                subtitle: '68.2ms • Legacy XML classifier • Classical Viola-Jones Baseline',
                badge: 'LEGACY',
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppTheme.discordPurple : primaryTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      color: primaryTextColor,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Empirical Benchmark',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          Text(
                            'Real-World Edge CPU vs Base Papers 1 & 2',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    // Active Detector Button
                    InkWell(
                      onTap: _showDetectorPickerModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.discordBlurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.discordBlurple.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.tune_rounded, size: 14, color: AppTheme.discordBlurple),
                            const SizedBox(width: 6),
                            Text(
                              widget.engine.activeDetector.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.discordBlurple,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.discordBlurple),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // Scenario Selector Horizontal Carousel
                    SizedBox(
                      height: 42,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _scenarios.length,
                        itemBuilder: (ctx, idx) {
                          final sc = _scenarios[idx];
                          final isSelected = idx == _selectedScenarioIndex;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text('${sc['id']}: ${sc['name'].toString().split(': ').last}'),
                              selected: isSelected,
                              selectedColor: AppTheme.discordBlurple.withValues(alpha: 0.25),
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? AppTheme.discordBlurple : primaryTextColor,
                              ),
                              side: BorderSide(
                                color: isSelected ? AppTheme.discordBlurple : (isDark ? Colors.white12 : Colors.black12),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              onSelected: (_) => setState(() => _selectedScenarioIndex = idx),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Active Scenario Card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  currentScenario['name'],
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.discordBlurple.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${currentScenario['students']} Students',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.discordBlurple),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              currentScenario['desc'],
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
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

                    // ClassRoom Proposed vs Base Paper 1 Comparison Card
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
                                Text(
                                  'Empirical Metrics vs. Literature',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor),
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
                                    baselineValue: currentScenario['paper1_f1'],
                                    isPositive: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildComparisonTile(
                                    title: 'Inference Latency',
                                    ourValue: currentScenario['yunet_time'],
                                    baselineValue: currentScenario['paper1_time'],
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
                                    baselineValue: '72.2% (No SAHI)',
                                    isPositive: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildComparisonTile(
                                    title: 'False Absence Rate',
                                    ourValue: currentScenario['far'],
                                    baselineValue: '27.8% (Symmetric)',
                                    isPositive: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Base Paper 2 Architecture Comparison Card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shield_outlined, color: AppTheme.discordGreen, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Architecture: ClassRoom vs Bugingo et al. 2025',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildArchRow(
                              label: 'Capture Hardware',
                              ours: 'Handheld Smartphone (10s sweep)',
                              theirs: 'Fixed Ceiling Surveillance Cameras',
                            ),
                            _buildArchRow(
                              label: 'Compute Device',
                              ours: '100% Commodity Mobile CPU',
                              theirs: 'Dedicated Cloud Server Instance',
                            ),
                            _buildArchRow(
                              label: 'Privacy & Security',
                              ours: 'Local SQLite (Zero Cloud Biometrics)',
                              theirs: 'Google Firebase Cloud Sync',
                            ),
                            _buildArchRow(
                              label: 'Installation Cost',
                              ours: '\$0 (Teacher\'s existing phone)',
                              theirs: '\$2000+ per lecture hall cabling',
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
                        label: Text(_isPickingVideo ? 'Analyzing Video...' : 'Run Benchmark on Classroom Sweep Video'),
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
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black54)),
                  Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
                ],
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
    required String baselineValue,
    required bool isPositive,
    bool isSpeed = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                ourValue,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.discordGreen),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_upward_rounded, size: 12, color: AppTheme.discordGreen),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Baseline: $baselineValue',
            style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _buildArchRow({
    required String label,
    required String ours,
    required String theirs,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF2F3F5) : const Color(0xFF23272A);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryTextColor),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ ClassRoom: $ours',
                  style: const TextStyle(fontSize: 11, color: AppTheme.discordGreen),
                ),
                Text(
                  '✗ Baseline: $theirs',
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
