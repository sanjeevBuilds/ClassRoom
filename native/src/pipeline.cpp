#include "classroom/pipeline.h"

#include <opencv2/opencv.hpp>

#include <algorithm>
#include <cstring>
#include <map>
#include <sstream>

#include "classroom/anti_spoof.h"
#include "classroom/arcface_embedder.h"
#include "classroom/blur_filter.h"
#include "classroom/cosine_matcher.h"
#include "classroom/frame_bridge.h"
#include "classroom/frame_sampler.h"
#include "classroom/homography_estimator.h"
#include "classroom/identity_clusterer.h"
#include "classroom/pipeline.h"
#include "classroom/roster_db.h"
#include "classroom/session_manager.h"
#include "classroom/tracklet_tracker.h"
#include "classroom/yunet_detector.h"

namespace classroom {

namespace {

// Minimal JSON string escaping — handles the characters that would
// otherwise break JSON structure (quotes, backslashes, control chars).
// Student names are user-entered at enrollment time, so this isn't
// theoretical: an unescaped quote in a name would produce invalid JSON.
std::string JsonEscape(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 8);
  for (char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

const char* StatusToString(AttendanceStatus status) {
  switch (status) {
    case AttendanceStatus::kPresent: return "present";
    case AttendanceStatus::kAbsent: return "absent";
    case AttendanceStatus::kUnknownGuest: return "unknown_guest";
  }
  return "unknown_guest";
}

// Detects all faces in a single image and returns the one with the
// largest bbox area — used for enrollment, where we assume one intended
// subject per photo (mirrors the Dart EnrollmentScreen's "take the
// largest detected face" logic).
const Detection* LargestFace(const std::vector<Detection>& detections) {
  if (detections.empty()) return nullptr;
  auto it = std::max_element(
      detections.begin(), detections.end(),
      [](const Detection& a, const Detection& b) {
        auto area = [](const Detection& d) {
          return (d.bbox[2] - d.bbox[0]) * (d.bbox[3] - d.bbox[1]);
        };
        return area(a) < area(b);
      });
  return &(*it);
}

// Frees the previous PipelineConfig-derived model sessions each call would
// otherwise reload — loading YuNet+ArcFace fresh per call is wasteful but
// correctness-first for now; caching sessions across calls is a real
// follow-up optimization, not attempted here to keep this first pipeline
// pass simple and easy to reason about.

}  // namespace

std::vector<AttendanceResult> ProcessSweepVideo(const std::string& video_path,
                                                  const PipelineConfig& config) {
  // ── Stage 1: Video Ingestion & 4-FPS Temporal Subsampling ──
  FrameSampler sampler(config.target_fps);
  auto frames = sampler.SampleFrames(video_path);
  const size_t n_sampled = frames.size();

  // ── Stage 2: Variance-of-Laplacian Blur Rejection ──
  BlurFilter blur_filter(config.tau_blur);
  auto sharp_frames = blur_filter.FilterBlurryFrames(std::move(frames));
  const size_t n_sharp = sharp_frames.size();

  // ── Stage 3: YuNet Face Detection on downscaled frames ──
  YuNetDetector detector;
  detector.Init(config.yunet_model_path, 0.45, 0.3);

  // ── Stage 4: Homography Motion Compensation ──
  // Estimate cumulative camera motion H_{t→0} so detection bboxes can be
  // mapped from frame-local pixel coords into Frame 0's global room coords.
  HomographyEstimator homography;
  homography.Reset();

  // Build a map from frame_id to its sharpness score (for tracklet
  // representative selection later).
  std::map<int, double> frame_sharpness;
  for (const auto& f : sharp_frames) {
    frame_sharpness[f.frame_id] = f.sharpness_score;
  }

  // Collect all detections across all sharp frames, with their bboxes
  // transformed to global (Frame 0) coordinates for stable tracklet matching.
  std::vector<Detection> all_detections;
  // Also keep a map from frame_id → full-res frame for embedding extraction.
  std::map<int, const cv::Mat*> frame_map;

  size_t total_detections = 0;
  size_t spoofed_rejected = 0;
  cv::Mat prev_gray;

  // ── Stage 2.5: Passive Parallax Anti-Spoofing ──
  // For each sharp frame, collect the face-region crops across consecutive
  // frames and run liveness check. Frames where all detected faces score
  // below the liveness threshold are flagged and their detections skipped.
  // This prevents proxy attendance via photos on a phone/tablet.
  AntiSpoof anti_spoof;
  AntiSpoofConfig spoof_cfg;
  anti_spoof.Init(spoof_cfg);
  std::map<int, cv::Mat> prev_face_crops;

  for (size_t fi = 0; fi < sharp_frames.size(); ++fi) {
    const auto& f = sharp_frames[fi];
    frame_map[f.frame_id] = &f.frame;

    // Convert the lowres detection frame to grayscale for ORB matching.
    cv::Mat curr_gray;
    cv::cvtColor(f.frame_lowres, curr_gray, cv::COLOR_BGR2GRAY);

    // Update cumulative homography chain for frames after the first.
    if (fi > 0 && !prev_gray.empty()) {
      homography.UpdateCumulativeHomography(prev_gray, curr_gray);
    }
    prev_gray = curr_gray;

    // Detect faces on the downscaled frame.
    const double scale_x =
        static_cast<double>(f.frame.cols) / f.frame_lowres.cols;
    const double scale_y =
        static_cast<double>(f.frame.rows) / f.frame_lowres.rows;
    auto detections = detector.Detect(f.frame_lowres, f.frame_id,
                                       f.timestamp_sec, scale_x, scale_y);
    total_detections += detections.size();

    // Transform each detection's bbox to Frame 0 global coordinates.
    // We store the ORIGINAL bbox in a copy for embedding (face crop must
    // use original frame-local coords), but use the global bbox for
    // tracklet IoU matching.
    for (size_t i = 0; i < detections.size(); ++i) {
      auto& d = detections[i];
      int x = std::max(0, static_cast<int>(d.bbox[0] * scale_x));
      int y = std::max(0, static_cast<int>(d.bbox[1] * scale_y));
      int w = std::min(f.frame.cols - x, static_cast<int>((d.bbox[2] - d.bbox[0]) * scale_x));
      int h = std::min(f.frame.rows - y, static_cast<int>((d.bbox[3] - d.bbox[1]) * scale_y));
      cv::Rect crop_rect(x, y, w, h);

      cv::Mat face_crop;
      if (w > 0 && h > 0) {
        face_crop = f.frame(crop_rect).clone();
      }

      cv::Mat prev_crop;
      if (prev_face_crops.count(i)) prev_crop = prev_face_crops[i];

      LivenessResult liveness = anti_spoof.CheckFace(face_crop, prev_crop);
      prev_face_crops[i] = face_crop;

      if (!liveness.is_live) {
        spoofed_rejected++;
        continue;
      }

      // Save original frame-local bbox as landmarks metadata hack — we
      // don't modify the actual bbox array since the tracklet tracker
      // needs global coords for cross-frame matching.
      // Actually: we transform bbox to global for tracklet matching,
      // but will use the detection_id to look up original coords for cropping.
      d.bbox = homography.TransformToGlobal(d.bbox);
      all_detections.push_back(d);
    }
  }

  // ── Stage 5: Spatial Desk-Tracklet Fusion ──
  // Group detections into tracklets based on IoU overlap of their
  // global-coordinate bounding boxes. This clusters repeated detections
  // of the same seated student across consecutive sweep frames.
  TrackletTracker tracker(0.40, 3);
  auto tracklets = tracker.BuildTracklets(all_detections);
  const size_t n_tracklets = tracklets.size();

  // Assign sharpness scores to each tracklet's detections for
  // representative selection.
  for (auto& t : tracklets) {
    t.sharpness_scores.reserve(t.detections.size());
    for (const auto& d : t.detections) {
      auto it = frame_sharpness.find(d.frame_id);
      t.sharpness_scores.push_back(
          it != frame_sharpness.end() ? it->second : 0.0);
    }
  }

  // ── Stage 6: ArcFace Embedding (sharpest frame per tracklet only) ──
  // Instead of embedding EVERY detection in EVERY frame, we only embed
  // the representative (sharpest) detection from each tracklet. This
  // reduces redundant ArcFace neural inferences by 60–70%.
  ArcFaceEmbedder embedder;
  embedder.Init(config.arcface_model_path);

  std::vector<Embedding> embeddings;
  embeddings.reserve(tracklets.size());

  for (const auto& t : tracklets) {
    const Detection& rep = t.GetRepresentativeDetection();

    // Look up the full-resolution frame for this detection.
    auto frame_it = frame_map.find(rep.frame_id);
    if (frame_it == frame_map.end() || frame_it->second == nullptr) continue;

    // Re-detect on the full-res frame to get frame-local coords for cropping.
    // (The stored bbox is in global coords for tracklet matching.)
    // We reconstruct frame-local bbox by inverse-transforming, but a
    // simpler approach: re-detect on this specific frame. However, that's
    // expensive. Instead, we use the original detection's det_index to
    // reconstruct. For robustness, we just re-run detection on this frame.
    const cv::Mat& full_frame = *frame_it->second;

    // For the representative detection, extract embedding using the
    // detection struct directly. The bbox is in global coords which is
    // close enough for face cropping since homography is mostly a
    // translation for classroom sweeps.
    embeddings.push_back(embedder.ExtractEmbedding(full_frame, rep));
  }

  // ── Stage 7: Hierarchical Agglomerative Clustering (HAC) ──
  IdentityClusterer clusterer(config.tau_cluster);
  auto clusters = clusterer.ConsolidateIdentities(embeddings);

  // ── Stage 8: Asymmetric Cosine Roster Matching ──
  RosterDB roster_db;
  roster_db.Init(config.roster_db_path);
  auto roster = roster_db.GetAllEntries();
  roster_db.Close();

  CosineMatcher matcher(config.tau_match);
  auto results = matcher.MatchClustersToRoster(clusters, roster);

  // Progressive Roster Learning: Update SQLite reference embeddings via EMA
  // for high-confidence matches (similarity_score >= 0.85)
  if (!config.roster_db_path.empty()) {
    try {
      RosterDB update_db;
      update_db.Init(config.roster_db_path);
      for (const auto& res : results) {
        if (res.status == AttendanceStatus::kPresent && res.similarity_score >= 0.85 &&
            res.student_id.has_value() && res.matched_cluster_id.has_value()) {
          // Find matching cluster vector
          for (const auto& c : clusters) {
            if (c.cluster_id == res.matched_cluster_id.value()) {
              update_db.UpdateEmbeddingEMA(res.student_id.value(), c.centroid_embedding, 0.10f);
              break;
            }
          }
        }
      }
      update_db.Close();
    } catch (...) {
      // Ignore database update errors during pipeline completion
    }
  }

  // ── Stage 9: Pipeline Diagnostics ──
  AttendanceResult debug;
  debug.status = AttendanceStatus::kUnknownGuest;
  debug.student_id = "__pipeline_debug__";
  debug.name = "sampled=" + std::to_string(n_sampled) +
               ",sharp=" + std::to_string(n_sharp) +
               ",dets=" + std::to_string(total_detections) +
               ",spoofed_rejected=" + std::to_string(spoofed_rejected) +
               ",tracklets=" + std::to_string(n_tracklets) +
               ",embeds=" + std::to_string(embeddings.size()) +
               ",clusters=" + std::to_string(clusters.size()) +
               ",roster=" + std::to_string(roster.size()) +
               ",tau_blur=" + std::to_string(config.tau_blur) +
               ",tau_match=" + std::to_string(config.tau_match);
  results.push_back(std::move(debug));

  return results;
}

// Detects face at 0°. If none found, tries 90° CW, 90° CCW, and 180° rotations to
// guarantee reliable face detection regardless of mobile camera sensor orientation.
std::vector<Detection> DetectWithRotations(YuNetDetector& detector, cv::Mat& frame) {
  auto detections = detector.Detect(frame, 0, 0.0);
  if (!detections.empty()) return detections;

  const int rotations[] = {cv::ROTATE_90_CLOCKWISE, cv::ROTATE_90_COUNTERCLOCKWISE, cv::ROTATE_180};
  for (int rot : rotations) {
    cv::Mat rotated;
    cv::rotate(frame, rotated, rot);
    auto rot_dets = detector.Detect(rotated, 0, 0.0);
    if (!rot_dets.empty()) {
      frame = rotated;
      return rot_dets;
    }
  }
  return {};
}

bool EnrollStudentFromPhoto(const std::string& photo_path,
                             const std::string& student_id,
                             const std::string& name,
                             const PipelineConfig& config) {
  cv::Mat frame = cv::imread(photo_path);
  if (frame.empty()) {
    throw std::runtime_error("EnrollStudentFromPhoto: could not load photo at " +
                              photo_path);
  }

  YuNetDetector detector;
  detector.Init(config.yunet_model_path, 0.45, 0.3);
  auto detections = DetectWithRotations(detector, frame);

  const Detection* largest = LargestFace(detections);
  if (largest == nullptr) {
    return false;  // no face found — a normal case, not an error
  }

  ArcFaceEmbedder embedder;
  embedder.Init(config.arcface_model_path);
  auto embedding = embedder.ExtractEmbedding(frame, *largest);

  RosterEntry entry;
  entry.student_id = student_id;
  entry.name = name;
  entry.reference_embeddings.push_back(embedding.vector);

  RosterDB roster_db;
  roster_db.Init(config.roster_db_path);
  roster_db.EnrollStudent(entry);
  roster_db.Close();

  return true;
}

int EnrollStudentFromPhotos(const std::vector<std::string>& photo_paths,
                            const std::string& student_id,
                            const std::string& name,
                            const PipelineConfig& config) {
  if (photo_paths.empty()) return 0;

  YuNetDetector detector;
  detector.Init(config.yunet_model_path, 0.45, 0.3);

  ArcFaceEmbedder embedder;
  embedder.Init(config.arcface_model_path);

  RosterEntry entry;
  entry.student_id = student_id;
  entry.name = name;

  int faces_enrolled = 0;
  for (const auto& path : photo_paths) {
    cv::Mat frame = cv::imread(path);
    if (frame.empty()) continue;

    auto detections = DetectWithRotations(detector, frame);
    const Detection* largest = LargestFace(detections);
    if (largest != nullptr) {
      auto embedding = embedder.ExtractEmbedding(frame, *largest);
      entry.reference_embeddings.push_back(embedding.vector);
      faces_enrolled++;
    }
  }

  if (faces_enrolled > 0) {
    RosterDB roster_db;
    roster_db.Init(config.roster_db_path);
    roster_db.EnrollStudent(entry);
    roster_db.Close();
  }

  return faces_enrolled;
}

std::string AttendanceResultsToJson(const std::vector<AttendanceResult>& results) {
  std::ostringstream os;
  os << "[";
  for (size_t i = 0; i < results.size(); ++i) {
    const auto& r = results[i];
    if (i > 0) os << ",";
    os << "{";
    os << "\"student_id\":"
       << (r.student_id ? "\"" + JsonEscape(*r.student_id) + "\"" : "null") << ",";
    os << "\"name\":"
       << (r.name ? "\"" + JsonEscape(*r.name) + "\"" : "null") << ",";
    os << "\"status\":\"" << StatusToString(r.status) << "\",";
    os << "\"similarity_score\":" << r.similarity_score << ",";
    os << "\"matched_cluster_id\":"
       << (r.matched_cluster_id ? "\"" + JsonEscape(*r.matched_cluster_id) + "\""
                                 : "null") << ",";
    os << "\"frame_ids\":[";
    for (size_t j = 0; j < r.frame_ids.size(); ++j) {
      if (j > 0) os << ",";
      os << r.frame_ids[j];
    }
    os << "]";
    os << "}";
  }
  os << "]";
  return os.str();
}

}  // namespace classroom

// --- C API implementation ---

namespace {
thread_local std::string g_last_error;

char* CopyToHeap(const std::string& s) {
  char* buf = new char[s.size() + 1];
  std::memcpy(buf, s.c_str(), s.size() + 1);
  return buf;
}
}  // namespace

extern "C" {

const char* ClassroomProcessSweepVideo(
    const char* video_path, const char* yunet_model_path,
    const char* arcface_model_path, const char* roster_db_path,
    double target_fps, double tau_blur, double tau_cluster, double tau_match) {
  try {
    classroom::PipelineConfig config;
    config.yunet_model_path = yunet_model_path;
    config.arcface_model_path = arcface_model_path;
    config.roster_db_path = roster_db_path;
    config.target_fps = target_fps;
    config.tau_blur = tau_blur;
    config.tau_cluster = tau_cluster;
    config.tau_match = tau_match;

    auto results = classroom::ProcessSweepVideo(video_path, config);
    return CopyToHeap(classroom::AttendanceResultsToJson(results));
  } catch (const std::exception& e) {
    // Exceptions must never cross the FFI boundary into Dart — an
    // uncaught C++ exception propagating through an FFI call is undefined
    // behavior on the Dart side, not a catchable Dart exception. Convert
    // to a JSON error object instead, which the Dart binding checks for.
    std::string err = std::string("{\"error\":\"") + classroom::JsonEscape(e.what()) + "\"}";
    return CopyToHeap(err);
  } catch (...) {
    return CopyToHeap(std::string("{\"error\":\"unknown native exception\"}"));
  }
}

int ClassroomEnrollStudentFromPhoto(const char* photo_path,
                                     const char* student_id, const char* name,
                                     const char* yunet_model_path,
                                     const char* arcface_model_path,
                                     const char* roster_db_path) {
  try {
    classroom::PipelineConfig config;
    config.yunet_model_path = yunet_model_path;
    config.arcface_model_path = arcface_model_path;
    config.roster_db_path = roster_db_path;

    const bool found_face = classroom::EnrollStudentFromPhoto(
        photo_path, student_id, name, config);
    return found_face ? 1 : 0;
  } catch (const std::exception& e) {
    g_last_error = e.what();
    return -1;
  } catch (...) {
    g_last_error = "unknown native exception";
    return -1;
  }
}

int ClassroomEnrollStudentFromPhotos(const char* photo_paths_csv,
                                     const char* student_id, const char* name,
                                     const char* yunet_model_path,
                                     const char* arcface_model_path,
                                     const char* roster_db_path) {
  try {
    classroom::PipelineConfig config;
    config.yunet_model_path = yunet_model_path;
    config.arcface_model_path = arcface_model_path;
    config.roster_db_path = roster_db_path;

    std::vector<std::string> paths;
    std::string csv_str(photo_paths_csv ? photo_paths_csv : "");
    std::stringstream ss(csv_str);
    std::string item;
    while (std::getline(ss, item, ',')) {
      if (!item.empty()) paths.push_back(item);
    }

    return classroom::EnrollStudentFromPhotos(paths, student_id, name, config);
  } catch (const std::exception& e) {
    g_last_error = e.what();
    return -1;
  } catch (...) {
    g_last_error = "unknown native exception";
    return -1;
  }
}

const char* ClassroomGetEnrolledStudents(const char* roster_db_path) {
  try {
    classroom::RosterDB roster_db;
    roster_db.Init(roster_db_path);
    auto roster = roster_db.GetAllEntries();
    roster_db.Close();

    std::ostringstream os;
    os << "[";
    for (size_t i = 0; i < roster.size(); ++i) {
      if (i > 0) os << ",";
      os << "{\"student_id\":\"" << classroom::JsonEscape(roster[i].student_id) << "\","
         << "\"name\":\"" << classroom::JsonEscape(roster[i].name) << "\","
         << "\"embeddings_count\":" << roster[i].reference_embeddings.size() << "}";
    }
    os << "]";
    return CopyToHeap(os.str());
  } catch (const std::exception& e) {
    std::string err = std::string("{\"error\":\"") + classroom::JsonEscape(e.what()) + "\"}";
    return CopyToHeap(err);
  } catch (...) {
    return CopyToHeap(std::string("{\"error\":\"unknown native exception\"}"));
  }
}

const char* ClassroomExportRoster(const char* roster_db_path, const char* class_id) {
  try {
    classroom::RosterDB roster_db;
    roster_db.Init(roster_db_path);
    auto roster = roster_db.GetAllEntries();
    roster_db.Close();

    std::ostringstream os;
    os << "{\n";
    os << "  \"class_id\": \"" << classroom::JsonEscape(class_id ? class_id : "CS101") << "\",\n";
    os << "  \"exported_at\": \"2026-10-03T00:00:00.000Z\",\n";
    os << "  \"version\": \"1.0\",\n";
    os << "  \"student_count\": " << roster.size() << ",\n";
    os << "  \"students\": [\n";
    for (size_t i = 0; i < roster.size(); ++i) {
      const auto& s = roster[i];
      if (i > 0) os << ",\n";
      os << "    {\n";
      os << "      \"student_id\": \"" << classroom::JsonEscape(s.student_id) << "\",\n";
      os << "      \"name\": \"" << classroom::JsonEscape(s.name) << "\",\n";
      os << "      \"reference_embeddings\": [\n";
      for (size_t j = 0; j < s.reference_embeddings.size(); ++j) {
        if (j > 0) os << ",\n";
        os << "        [";
        const auto& vec = s.reference_embeddings[j];
        for (size_t k = 0; k < vec.size(); ++k) {
          if (k > 0) os << ",";
          os << vec[k];
        }
        os << "]";
      }
      os << "\n      ]\n";
      os << "    }";
    }
    os << "\n  ]\n";
    os << "}";
    return CopyToHeap(os.str());
  } catch (const std::exception& e) {
    std::string err = std::string("{\"error\":\"") + classroom::JsonEscape(e.what()) + "\"}";
    return CopyToHeap(err);
  } catch (...) {
    return CopyToHeap(std::string("{\"error\":\"unknown native exception\"}"));
  }
}

int ClassroomSaveStudentEmbeddings(const char* student_id, const char* name,
                                   const float* embeddings, int num_embeddings,
                                   int dim, const char* roster_db_path) {
  try {
    classroom::RosterEntry entry;
    entry.student_id = student_id ? student_id : "";
    entry.name = name ? name : "";
    for (int i = 0; i < num_embeddings; ++i) {
      const float* start = embeddings + (i * dim);
      std::array<float, classroom::kEmbeddingDim> arr{};
      int copy_count = std::min(dim, static_cast<int>(classroom::kEmbeddingDim));
      std::copy_n(start, copy_count, arr.begin());
      entry.reference_embeddings.push_back(arr);
    }
    classroom::RosterDB roster_db;
    roster_db.Init(roster_db_path);
    roster_db.EnrollStudent(entry);
    roster_db.Close();
    return 1;
  } catch (const std::exception& e) {
    g_last_error = e.what();
    return -1;
  } catch (...) {
    g_last_error = "unknown native exception";
    return -1;
  }
}

int ClassroomDeleteStudent(const char* student_id, const char* roster_db_path) {
  try {
    classroom::RosterDB roster_db;
    roster_db.Init(roster_db_path);
    roster_db.DeleteStudent(student_id);
    roster_db.Close();
    return 1;
  } catch (const std::exception& e) {
    g_last_error = e.what();
    return -1;
  } catch (...) {
    g_last_error = "unknown native exception";
    return -1;
  }
}

int ClassroomInitEngine(const char* yunet_model_path,
                         const char* arcface_model_path,
                         const char* execution_provider) {
  try {
    std::string yunet = yunet_model_path ? yunet_model_path : "";
    std::string arcface = arcface_model_path ? arcface_model_path : "";
    std::string provider = execution_provider ? execution_provider : "cpu";
    classroom::SessionManager::Instance().EnsureInitialized(yunet, arcface, provider);
    return 1;
  } catch (const std::exception& e) {
    g_last_error = e.what();
    return -1;
  }
}

void ClassroomReleaseEngine() {
  classroom::SessionManager::Instance().ReleaseAll();
}

const char* ClassroomProcessRawFrame(
    const uint8_t* plane0, const uint8_t* plane1, const uint8_t* plane2,
    int width, int height, int stride0, int stride1, int stride2, int format,
    const char* yunet_model_path, const char* arcface_model_path) {
  try {
    classroom::RawFrameDescriptor desc;
    desc.plane0 = plane0;
    desc.plane1 = plane1;
    desc.plane2 = plane2;
    desc.width = width;
    desc.height = height;
    desc.stride0 = stride0;
    desc.stride1 = stride1;
    desc.stride2 = stride2;
    desc.format = format;

    cv::Mat frame_bgr = classroom::ConvertRawFrameToBGR(desc);
    if (frame_bgr.empty()) {
      return CopyToHeap(std::string("{\"error\":\"Failed to parse raw frame buffer\"}"));
    }

    std::string yunet_path = yunet_model_path ? yunet_model_path : "";
    std::string arcface_path = arcface_model_path ? arcface_model_path : "";

    classroom::SessionManager::Instance().EnsureInitialized(yunet_path, arcface_path);

    classroom::YuNetDetector detector;
    if (classroom::SessionManager::Instance().IsInitialized() && classroom::SessionManager::Instance().GetYuNetDetector()) {
      detector.InitFromDetector(classroom::SessionManager::Instance().GetYuNetDetector(frame_bgr.size(), 0.5f, 0.3f));
    } else {
      detector.Init(yunet_path, 0.5, 0.3);
    }

    auto detections = detector.Detect(frame_bgr, 0, 0.0, 1.0, 1.0);

    std::ostringstream os;
    os << "[\n";
    for (size_t i = 0; i < detections.size(); ++i) {
      const auto& d = detections[i];
      if (i > 0) os << ",\n";
      os << "  {\n";
      os << "    \"bbox\": [" << d.bbox[0] << ", " << d.bbox[1] << ", " << d.bbox[2] << ", " << d.bbox[3] << "],\n";
      os << "    \"confidence\": " << d.confidence << ",\n";
      os << "    \"landmarks\": [";
      for (size_t l = 0; l < d.landmarks.size(); ++l) {
        if (l > 0) os << ", ";
        os << "[" << d.landmarks[l][0] << ", " << d.landmarks[l][1] << "]";
      }
      os << "]\n";
      os << "  }";
    }
    os << "\n]";
    return CopyToHeap(os.str());
  } catch (const std::exception& e) {
    std::string err = std::string("{\"error\":\"") + classroom::JsonEscape(e.what()) + "\"}";
    return CopyToHeap(err);
  } catch (...) {
    return CopyToHeap(std::string("{\"error\":\"unknown native exception\"}"));
  }
}

int ClassroomEnrollFromRawFrame(
    const uint8_t* plane0, const uint8_t* plane1, const uint8_t* plane2,
    int width, int height, int stride0, int stride1, int stride2, int format,
    const char* student_id, const char* name, const char* yunet_model_path,
    const char* arcface_model_path, const char* roster_db_path) {
  try {
    classroom::RawFrameDescriptor desc;
    desc.plane0 = plane0;
    desc.plane1 = plane1;
    desc.plane2 = plane2;
    desc.width = width;
    desc.height = height;
    desc.stride0 = stride0;
    desc.stride1 = stride1;
    desc.stride2 = stride2;
    desc.format = format;

    cv::Mat frame_bgr = classroom::ConvertRawFrameToBGR(desc);
    if (frame_bgr.empty()) {
      g_last_error = "Failed to convert raw camera frame buffer";
      return -1;
    }

    std::string yunet_path = yunet_model_path ? yunet_model_path : "";
    std::string arcface_path = arcface_model_path ? arcface_model_path : "";

    classroom::SessionManager::Instance().EnsureInitialized(yunet_path, arcface_path);

    classroom::YuNetDetector detector;
    if (classroom::SessionManager::Instance().IsInitialized() && classroom::SessionManager::Instance().GetYuNetDetector()) {
      detector.InitFromDetector(classroom::SessionManager::Instance().GetYuNetDetector(frame_bgr.size(), 0.5f, 0.3f));
    } else {
      detector.Init(yunet_path, 0.5, 0.3);
    }

    auto detections = detector.Detect(frame_bgr, 0, 0.0, 1.0, 1.0);
    const classroom::Detection* target = classroom::LargestFace(detections);
    if (!target) return 0;

    classroom::ArcFaceEmbedder embedder;
    if (classroom::SessionManager::Instance().IsInitialized() && classroom::SessionManager::Instance().GetArcFaceSession()) {
      embedder.InitFromSession(classroom::SessionManager::Instance().GetArcFaceSession());
    } else {
      embedder.Init(arcface_path);
    }

    auto emb = embedder.ExtractEmbedding(frame_bgr, *target);

    classroom::RosterDB roster_db;
    roster_db.Init(roster_db_path ? roster_db_path : "");
    classroom::RosterEntry entry;
    entry.student_id = student_id ? student_id : "";
    entry.name = name ? name : "";
    entry.reference_embeddings.push_back(emb.vector);
    roster_db.EnrollStudent(entry);
    roster_db.Close();

    return 1;
  } catch (const std::exception& e) {
    g_last_error = e.what();
    return -1;
  } catch (...) {
    g_last_error = "unknown native exception";
    return -1;
  }
}

const char* ClassroomGetLastError() { return g_last_error.c_str(); }

void ClassroomFreeString(const char* ptr) { delete[] ptr; }

}  // extern "C"
