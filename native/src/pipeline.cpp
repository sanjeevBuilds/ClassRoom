#include "classroom/pipeline.h"

#include <opencv2/opencv.hpp>

#include <algorithm>
#include <cstring>
#include <sstream>

#include "classroom/arcface_embedder.h"
#include "classroom/blur_filter.h"
#include "classroom/cosine_matcher.h"
#include "classroom/desk_tracker.h"
#include "classroom/face_pose.h"
#include "classroom/frame_sampler.h"
#include "classroom/homography.h"
#include "classroom/identity_clusterer.h"
#include "classroom/lighting_enhancer.h"
#include "classroom/roster_db.h"
#include "classroom/sahi_slicing.h"
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
  FrameSampler sampler(config.target_fps);
  auto frames = sampler.SampleFrames(video_path);
  const size_t n_sampled = frames.size();

  BlurFilter blur_filter(config.tau_blur);
  auto sharp_frames = blur_filter.FilterBlurryFrames(std::move(frames));
  const size_t n_sharp = sharp_frames.size();

  YuNetDetector detector;
  detector.Init(config.yunet_model_path, 0.45, 0.3);

  ArcFaceEmbedder embedder;
  embedder.Init(config.arcface_model_path);

  LightingEnhancer lighting_enhancer(85.0, 2.5);
  HomographyEstimator homography_estimator(0.15);
  FacePoseEstimator pose_estimator(45.0, 35.0, 50.0);
  DeskTracker desk_tracker(90.0, 6);
  SahiRearRowSlicer sahi_slicer(&detector, 0.60, 480, 360, 0.20, 0.45);

  cv::Mat prev_frame;
  size_t total_detections = 0;
  std::map<int, cv::Mat> frame_cache;

  for (auto& f : sharp_frames) {
    // 1. Adaptive Low-Light CLAHE
    cv::Mat enhanced_full = lighting_enhancer.EnhanceIfNeeded(f.frame);
    frame_cache[f.frame_id] = enhanced_full;

    // 2. Inter-Frame Camera Motion Estimation
    double dx = 0.0, dy = 0.0;
    if (!prev_frame.empty()) {
      homography_estimator.EstimateDisplacement(prev_frame, enhanced_full, dx, dy);
    }
    prev_frame = enhanced_full;

    const double scale_x =
        static_cast<double>(enhanced_full.cols) / f.frame_lowres.cols;
    const double scale_y =
        static_cast<double>(enhanced_full.rows) / f.frame_lowres.rows;

    // 3. Primary YuNet detection on downscaled frame
    auto global_detections = detector.Detect(f.frame_lowres, f.frame_id,
                                             f.timestamp_sec, scale_x, scale_y);

    // 4. SAHI Rear-Row Slicing for distant students (top 60% horizon)
    auto all_detections = sahi_slicer.DetectWithSlicing(
        enhanced_full, f.frame_id, f.timestamp_sec, global_detections);

    // 5. 6-Axis Pose Filtering: drop non-usable profile angles (|yaw| > 45°)
    std::vector<Detection> usable_detections;
    for (const auto& det : all_detections) {
      auto pose = pose_estimator.EstimatePose(det);
      if (pose_estimator.IsUsablePose(pose)) {
        usable_detections.push_back(det);
      }
    }

    total_detections += usable_detections.size();

    // 6. Spatial Desk-Tracklet Fusion
    desk_tracker.UpdateFrame(f.frame_id, usable_detections, 100.0, dx, dy);
  }

  // 7. Desk-Tracklet Exemplar Selection (Cuts ArcFace inferences by 65–70%)
  auto tracklets = desk_tracker.FinalizeTracklets();
  std::vector<Embedding> embeddings;

  for (const auto& tracklet : tracklets) {
    auto best_exemplars = tracklet.GetBestExemplars(2);
    for (const auto& det : best_exemplars) {
      auto it = frame_cache.find(det.frame_id);
      if (it != frame_cache.end() && !it->second.empty()) {
        try {
          embeddings.push_back(embedder.ExtractEmbedding(it->second, det));
        } catch (...) {
          // Ignore invalid crops or alignment failures
        }
      }
    }
  }

  IdentityClusterer clusterer(config.tau_cluster);
  auto clusters = clusterer.ConsolidateIdentities(embeddings);

  RosterDB roster_db;
  roster_db.Init(config.roster_db_path);
  auto roster = roster_db.GetAllEntries();
  roster_db.Close();

  CosineMatcher matcher(config.tau_match);
  auto results = matcher.MatchClustersToRoster(clusters, roster);

  // Append comprehensive diagnostic telemetry
  AttendanceResult debug;
  debug.status = AttendanceStatus::kUnknownGuest;
  debug.student_id = "__pipeline_debug__";
  debug.name = "sampled=" + std::to_string(n_sampled) +
               ",sharp=" + std::to_string(n_sharp) +
               ",dets=" + std::to_string(total_detections) +
               ",desks=" + std::to_string(tracklets.size()) +
               ",embeds=" + std::to_string(embeddings.size()) +
               ",clusters=" + std::to_string(clusters.size()) +
               ",roster=" + std::to_string(roster.size()) +
               ",tau_blur=" + std::to_string(config.tau_blur) +
               ",tau_match=" + std::to_string(config.tau_match);
  results.push_back(std::move(debug));

  return results;
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

  // 1. Aspect-ratio preserving downscale to max dimension 640 for fast detection
  int det_w = 640;
  int det_h = (640 * frame.rows) / frame.cols;
  if (frame.rows > frame.cols) {
    det_h = 640;
    det_w = (640 * frame.cols) / frame.rows;
  }
  det_w = (det_w / 2) * 2;
  det_h = (det_h / 2) * 2;

  cv::Mat det_frame;
  cv::resize(frame, det_frame, cv::Size(det_w, det_h));

  YuNetDetector detector;
  detector.Init(config.yunet_model_path, 0.45, 0.3);
  auto detections = detector.Detect(det_frame, 0, 0.0);

  // 2. Multi-rotation scan fallback if 0 faces found (handles 90°, 270°, 180° camera EXIF orientations)
  int rotation_code = -1;
  if (detections.empty()) {
    const std::vector<cv::RotateFlags> candidate_rotations = {
      cv::ROTATE_90_CLOCKWISE,
      cv::ROTATE_90_COUNTERCLOCKWISE,
      cv::ROTATE_180,
    };
    for (const auto rot : candidate_rotations) {
      cv::Mat rotated_det;
      cv::rotate(det_frame, rotated_det, rot);
      auto candidate_dets = detector.Detect(rotated_det, 0, 0.0);
      if (!candidate_dets.empty()) {
        detections = std::move(candidate_dets);
        rotation_code = rot;
        break;
      }
    }
  }

  if (rotation_code != -1) {
    cv::Mat rotated_full;
    cv::rotate(frame, rotated_full, rotation_code);
    frame = rotated_full;
    if (rotation_code != cv::ROTATE_180) {
      std::swap(det_w, det_h);
    }
  }

  if (detections.empty()) {
    return false;  // no face found — a normal case, not an error
  }

  // Scale detection coordinates back to full-res frame
  const double scale_x = static_cast<double>(frame.cols) / det_w;
  const double scale_y = static_cast<double>(frame.rows) / det_h;
  for (auto& d : detections) {
    d.bbox[0] *= scale_x;
    d.bbox[1] *= scale_y;
    d.bbox[2] *= scale_x;
    d.bbox[3] *= scale_y;
    for (auto& lm : d.landmarks) {
      if (lm.size() >= 2) {
        lm[0] *= scale_x;
        lm[1] *= scale_y;
      }
    }
  }

  const Detection* largest = LargestFace(detections);
  if (largest == nullptr) {
    return false;
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

const char* ClassroomGetLastError() { return g_last_error.c_str(); }

void ClassroomFreeString(const char* ptr) { delete[] ptr; }

}  // extern "C"
