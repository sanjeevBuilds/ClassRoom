import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../models/detection.dart';
import '../models/embedding.dart';
import '../modules/blur_motion/blur_filter.dart';
import '../modules/embedding_clustering/arcface_embedder.dart';
import '../modules/embedding_clustering/clustering.dart';
import '../modules/face_detection/yunet_detector.dart';
import '../modules/roster_matching/cosine_matcher.dart';
import '../modules/roster_matching/roster_db.dart';
import '../modules/video_ingestion/frame_sampler.dart';
import 'results_screen.dart';

/// Processing screen — runs the recorded sweep through the pipeline:
/// FrameSampler → BlurFilter → YuNetDetector → ArcFaceEmbedder →
/// IdentityClusterer → CosineMatcher, then navigates to [ResultsScreen].
///
/// MVP scope: single detector (YuNet only — RetinaFace/Haar Cascade are for
/// the full research benchmark, not this pipeline run) and no homography
/// motion compensation (embedding-only clustering, per the documented
/// fallback in docs/interface_contract.md).
class ProcessingScreen extends StatefulWidget {
  final String videoPath;
  final RosterDB rosterDb;
  final YuNetDetector detector;
  final ArcFaceEmbedder embedder;

  const ProcessingScreen({
    super.key,
    required this.videoPath,
    required this.rosterDb,
    required this.detector,
    required this.embedder,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String _stage = 'Sampling frames…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      setState(() => _stage = 'Sampling frames…');
      final sampler = FrameSampler(targetFps: 4.0);
      final frames = await sampler.sampleFrames(widget.videoPath);

      setState(() => _stage = 'Filtering blurry frames…');
      final blurFilter = BlurFilter();
      final sharpFrames = blurFilter.filterBlurryFrames(frames);

      setState(() => _stage = 'Detecting faces…');
      final allDetections = <Detection>[];
      final frameById = <int, cv.Mat>{};
      for (final frame in sharpFrames) {
        final frameId = frame['frame_id'] as int;
        final timestampSec = frame['timestamp_sec'] as double;
        final fullRes = frame['frame'] as cv.Mat;
        final lowRes = frame['frame_lowres'] as cv.Mat;
        frameById[frameId] = fullRes;

        final scaleX = fullRes.cols / lowRes.cols;
        final scaleY = fullRes.rows / lowRes.rows;
        final detections = await widget.detector.detect(
          lowRes,
          frameId: frameId,
          timestampSec: timestampSec,
          scaleX: scaleX,
          scaleY: scaleY,
        );
        allDetections.addAll(detections);
        lowRes.release();
      }

      setState(() => _stage = 'Extracting embeddings (${allDetections.length} faces)…');
      final embeddings = <Embedding>[];
      for (final detection in allDetections) {
        final frame = frameById[detection.frameId];
        if (frame == null) continue;
        embeddings.add(await widget.embedder.extractEmbedding(frame, detection));
      }
      for (final mat in frameById.values) {
        mat.release();
      }

      setState(() => _stage = 'Consolidating identities…');
      final clusterer = IdentityClusterer();
      final clusters = clusterer.consolidateIdentities(embeddings);

      setState(() => _stage = 'Matching roster…');
      final roster = await widget.rosterDb.getAllEntries();
      final matcher = CosineMatcher();
      final results = matcher.matchClustersToRoster(clusters, roster);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultsScreen(results: results)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Processing failed: $_error', textAlign: TextAlign.center),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_stage),
                ],
              ),
      ),
    );
  }
}
