#include "classroom/pipeline.h"

#include <opencv2/opencv.hpp>

#include <algorithm>
#include <cstring>
#include <sstream>

#include "classroom/arcface_embedder.h"
#include "classroom/blur_filter.h"
#include "classroom/cosine_matcher.h"
#include "classroom/frame_sampler.h"
#include "classroom/identity_clusterer.h"
#include "classroom/roster_db.h"
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
  detector.Init(config.yunet_model_path);

  ArcFaceEmbedder embedder;
  embedder.Init(config.arcface_model_path);

  size_t total_detections = 0;
  std::vector<Embedding> embeddings;
  for (const auto& f : sharp_frames) {
    const double scale_x =
        static_cast<double>(f.frame.cols) / f.frame_lowres.cols;
    const double scale_y =
        static_cast<double>(f.frame.rows) / f.frame_lowres.rows;
    auto detections = detector.Detect(f.frame_lowres, f.frame_id,
                                       f.timestamp_sec, scale_x, scale_y);
    total_detections += detections.size();
    for (const auto& d : detections) {
      embeddings.push_back(embedder.ExtractEmbedding(f.frame, d));
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

  // Stash pipeline diagnostics in a synthetic "debug" result at the end
  // so we can see where the pipeline drops data without changing the
  // JSON schema (the Dart side just ignores unknown statuses).
  // Format: "debug:sampled=N,sharp=N,dets=N,embeds=N,clusters=N,roster=N"
  AttendanceResult debug;
  debug.status = AttendanceStatus::kUnknownGuest;
  debug.student_id = "__pipeline_debug__";
  debug.name = "sampled=" + std::to_string(n_sampled) +
               ",sharp=" + std::to_string(n_sharp) +
               ",dets=" + std::to_string(total_detections) +
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

  YuNetDetector detector;
  detector.Init(config.yunet_model_path);
  auto detections = detector.Detect(frame, 0, 0.0);

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
    std::string err = std::string("{\"error\":\"") + e.what() + "\"}";
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

const char* ClassroomGetLastError() { return g_last_error.c_str(); }

void ClassroomFreeString(const char* ptr) { delete[] ptr; }

}  // extern "C"
