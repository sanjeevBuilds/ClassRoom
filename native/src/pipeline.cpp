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

// Computes Intersection over Union (IoU) between two bounding boxes [x1, y1, x2, y2].
// Used for deduplicating detections across full-frame and SAHI horizon zoom passes.
double ComputeIoU(const std::array<double, 4>& a, const std::array<double, 4>& b) {
  const double inter_x1 = std::max(a[0], b[0]);
  const double inter_y1 = std::max(a[1], b[1]);
  const double inter_x2 = std::min(a[2], b[2]);
  const double inter_y2 = std::min(a[3], b[3]);

  if (inter_x2 <= inter_x1 || inter_y2 <= inter_y1) {
    return 0.0;
  }

  const double inter_area = (inter_x2 - inter_x1) * (inter_y2 - inter_y1);
  const double area_a = (a[2] - a[0]) * (a[3] - a[1]);
  const double area_b = (b[2] - b[0]) * (b[3] - b[1]);
  const double union_area = area_a + area_b - inter_area;

  if (union_area <= 0.0) {
    return 0.0;
  }
  return inter_area / union_area;
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

  // Full-frame YuNet detector: calibrated threshold 0.40
  YuNetDetector detector;
  detector.Init(config.yunet_model_path, 0.40, 0.3);

  // SAHI Horizon YuNet detector: tuned sensitivity (0.35) for small distant rear-row faces (6-8m)
  YuNetDetector horizon_detector;
  horizon_detector.Init(config.yunet_model_path, 0.35, 0.3);

  ArcFaceEmbedder embedder;
  embedder.Init(config.arcface_model_path);

  size_t total_detections = 0;
  size_t total_horizon_detections = 0;
  // Auto-detect mobile video orientation: if raw video buffer is rotated (e.g. portrait
  // shot stored in landscape container), faces appear at 90° and YuNet detector finds 0 faces.
  // We probe the first sharp frame across rotations and re-align all frames upright if needed.
  int detected_rot = -1;
  for (const auto& sf : sharp_frames) {
    if (sf.frame_lowres.empty()) continue;
    auto test_dets = detector.Detect(sf.frame_lowres, 0, 0.0);
    if (!test_dets.empty()) {
      break;  // Already upright
    }
    const int candidate_rotations[] = {cv::ROTATE_90_CLOCKWISE,
                                       cv::ROTATE_90_COUNTERCLOCKWISE,
                                       cv::ROTATE_180};
    for (int rot : candidate_rotations) {
      cv::Mat rot_low;
      cv::rotate(sf.frame_lowres, rot_low, rot);
      auto r_dets = detector.Detect(rot_low, 0, 0.0);
      if (!r_dets.empty()) {
        detected_rot = rot;
        break;
      }
    }
    if (detected_rot != -1) break;
  }

  if (detected_rot != -1) {
    for (auto& sf : sharp_frames) {
      cv::Mat r_full, r_low;
      cv::rotate(sf.frame, r_full, detected_rot);
      cv::rotate(sf.frame_lowres, r_low, detected_rot);
      sf.frame = std::move(r_full);
      sf.frame_lowres = std::move(r_low);
    }
  }

  std::vector<Embedding> embeddings;

  for (const auto& f : sharp_frames) {
    if (f.frame.empty() || f.frame_lowres.empty()) {
      continue;
    }

    std::vector<Detection> frame_detections;

    // 1. Full-frame sweep (detects foreground & middle rows 1-5, down to 14px)
    const double scale_x =
        static_cast<double>(f.frame.cols) / f.frame_lowres.cols;
    const double scale_y =
        static_cast<double>(f.frame.rows) / f.frame_lowres.rows;
    auto full_dets = detector.Detect(f.frame_lowres, f.frame_id,
                                     f.timestamp_sec, scale_x, scale_y);

    for (auto& d : full_dets) {
      const double bw = d.bbox[2] - d.bbox[0];
      const double bh = d.bbox[3] - d.bbox[1];
      // Filter out degenerate artifacts smaller than 14px in original frame coordinates
      if (bw >= 14.0 && bh >= 14.0) {
        d.det_index = static_cast<int>(frame_detections.size());
        frame_detections.push_back(d);
        embeddings.push_back(embedder.ExtractEmbedding(f.frame, d));
        total_detections++;
      }
    }

    // 2. SAHI Horizon Zoom pass (2x magnification for rear rows 6-12 at 6-8 meters)
    // In typical classroom seating, rear rows appear in the upper 10% to 65% vertical window.
    const int horizon_y = std::max(0, static_cast<int>(f.frame.rows * 0.10));
    const int horizon_h = std::min(static_cast<int>(f.frame.rows * 0.55),
                                   f.frame.rows - horizon_y);

    if (horizon_h > 50 && f.frame.cols > 50) {
      std::vector<cv::Rect> horizon_crops;

      if (f.frame.cols > f.frame.rows && f.frame.cols >= 960) {
        // High-resolution landscape sweep: 3 overlapping tiles (Left, Center, Right)
        // Each tile covers ~40% width with ~10% horizontal overlap, yielding ~2.5x optical zoom
        const int tile_w = static_cast<int>(f.frame.cols * 0.40);
        const int left_x = 0;
        const int mid_x = static_cast<int>(f.frame.cols * 0.30);
        const int right_x = f.frame.cols - tile_w;

        horizon_crops.push_back(cv::Rect(left_x, horizon_y, tile_w, horizon_h));
        horizon_crops.push_back(cv::Rect(mid_x, horizon_y, tile_w, horizon_h));
        horizon_crops.push_back(cv::Rect(right_x, horizon_y, tile_w, horizon_h));
      } else if (f.frame.cols >= f.frame.rows) {
        // Standard landscape sweep: 2 overlapping tiles (Left, Right)
        const int tile_w = static_cast<int>(f.frame.cols * 0.58);
        const int right_x = f.frame.cols - tile_w;

        horizon_crops.push_back(cv::Rect(0, horizon_y, tile_w, horizon_h));
        horizon_crops.push_back(cv::Rect(right_x, horizon_y, tile_w, horizon_h));
      } else {
        // Portrait sweep: single upper horizon crop
        horizon_crops.push_back(cv::Rect(0, horizon_y, f.frame.cols, horizon_h));
      }

      for (const auto& crop : horizon_crops) {
        const int cx = std::clamp(crop.x, 0, f.frame.cols - 1);
        const int cy = std::clamp(crop.y, 0, f.frame.rows - 1);
        const int cw = std::clamp(crop.width, 1, f.frame.cols - cx);
        const int ch = std::clamp(crop.height, 1, f.frame.rows - cy);
        if (cw <= 50 || ch <= 50) continue;

        const cv::Rect safe_crop(cx, cy, cw, ch);
        cv::Mat sub_mat = f.frame(safe_crop);

        // Scale crop to 640 standard detection resolution
        const int max_dim = 640;
        int low_w, low_h;
        if (cw >= ch) {
          low_w = max_dim;
          low_h = std::max(1, static_cast<int>(std::lround(
                                  ch * (static_cast<double>(max_dim) / cw))));
        } else {
          low_h = max_dim;
          low_w = std::max(1, static_cast<int>(std::lround(
                                  cw * (static_cast<double>(max_dim) / ch))));
        }

        cv::Mat crop_lowres;
        cv::resize(sub_mat, crop_lowres, cv::Size(low_w, low_h));

        const double c_scale_x = static_cast<double>(cw) / low_w;
        const double c_scale_y = static_cast<double>(ch) / low_h;

        auto crop_dets = horizon_detector.Detect(crop_lowres, f.frame_id,
                                                 f.timestamp_sec, c_scale_x, c_scale_y);

        for (auto& hd : crop_dets) {
          // Remap coordinates back to the full high-res frame
          hd.bbox[0] += cx;
          hd.bbox[1] += cy;
          hd.bbox[2] += cx;
          hd.bbox[3] += cy;

          for (auto& lm : hd.landmarks) {
            lm[0] += cx;
            lm[1] += cy;
          }

          // Boundary clamp
          hd.bbox[0] = std::clamp(hd.bbox[0], 0.0, static_cast<double>(f.frame.cols - 1));
          hd.bbox[1] = std::clamp(hd.bbox[1], 0.0, static_cast<double>(f.frame.rows - 1));
          hd.bbox[2] = std::clamp(hd.bbox[2], hd.bbox[0] + 1.0, static_cast<double>(f.frame.cols));
          hd.bbox[3] = std::clamp(hd.bbox[3], hd.bbox[1] + 1.0, static_cast<double>(f.frame.rows));

          // Filter out noise < 14px in original frame
          const double bw = hd.bbox[2] - hd.bbox[0];
          const double bh = hd.bbox[3] - hd.bbox[1];
          if (bw < 14.0 || bh < 14.0) continue;

          // Deduplicate against already detected faces in this frame (IoU >= 0.35)
          bool is_dup = false;
          for (const auto& existing : frame_detections) {
            if (ComputeIoU(hd.bbox, existing.bbox) >= 0.35) {
              is_dup = true;
              break;
            }
          }

          if (!is_dup) {
            hd.det_index = static_cast<int>(frame_detections.size());
            frame_detections.push_back(hd);
            embeddings.push_back(embedder.ExtractEmbedding(f.frame, hd));
            total_detections++;
            total_horizon_detections++;
          }
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

  // Stash pipeline diagnostics in a synthetic "debug" result at the end
  // so we can see where the pipeline drops data without changing the
  // JSON schema (the Dart side just ignores unknown statuses).
  // Format: "debug:sampled=N,sharp=N,dets=N,horizon_dets=N,embeds=N,clusters=N,roster=N"
  AttendanceResult debug;
  debug.status = AttendanceStatus::kUnknownGuest;
  debug.student_id = "__pipeline_debug__";
  debug.name = "sampled=" + std::to_string(n_sampled) +
               ",sharp=" + std::to_string(n_sharp) +
               ",dets=" + std::to_string(total_detections) +
               ",horizon_dets=" + std::to_string(total_horizon_detections) +
               ",embeds=" + std::to_string(embeddings.size()) +
               ",clusters=" + std::to_string(clusters.size()) +
               ",roster=" + std::to_string(roster.size()) +
               ",tau_blur=" + std::to_string(config.tau_blur) +
               ",tau_match=" + std::to_string(config.tau_match);
  results.push_back(std::move(debug));

  return results;
}

// Detects face with scale-adaptive downscaling (to match YuNet's receptive field)
// and tries 0°, 90° CW, 90° CCW, and 180° rotations to guarantee reliable face
// detection regardless of mobile camera sensor resolution or orientation.
std::vector<Detection> DetectWithRotations(YuNetDetector& detector, cv::Mat& frame) {
  if (frame.empty()) return {};

  const int max_dim = 640;
  int low_w, low_h;
  if (frame.cols >= frame.rows) {
    low_w = max_dim;
    low_h = std::max(1, static_cast<int>(std::lround(
                            frame.rows * (static_cast<double>(max_dim) / frame.cols))));
  } else {
    low_h = max_dim;
    low_w = std::max(1, static_cast<int>(std::lround(
                            frame.cols * (static_cast<double>(max_dim) / frame.rows))));
  }

  cv::Mat lowres;
  cv::resize(frame, lowres, cv::Size(low_w, low_h));
  const double scale_x = static_cast<double>(frame.cols) / low_w;
  const double scale_y = static_cast<double>(frame.rows) / low_h;

  // 1. Try 0° rotation on downscaled image
  auto detections = detector.Detect(lowres, 0, 0.0, scale_x, scale_y);
  if (!detections.empty()) return detections;

  // 2. Try rotations (90° CW, 90° CCW, 180°) on downscaled image
  const int rotations[] = {cv::ROTATE_90_CLOCKWISE, cv::ROTATE_90_COUNTERCLOCKWISE, cv::ROTATE_180};
  for (int rot : rotations) {
    cv::Mat rot_low;
    cv::rotate(lowres, rot_low, rot);
    const double r_scale_x = static_cast<double>(rot == cv::ROTATE_180 ? frame.cols : frame.rows) / rot_low.cols;
    const double r_scale_y = static_cast<double>(rot == cv::ROTATE_180 ? frame.rows : frame.cols) / rot_low.rows;
    auto rot_dets = detector.Detect(rot_low, 0, 0.0, r_scale_x, r_scale_y);
    if (!rot_dets.empty()) {
      cv::Mat rot_frame;
      cv::rotate(frame, rot_frame, rot);
      frame = std::move(rot_frame);
      return rot_dets;
    }
  }

  // 3. Fallback: try raw high-res frame in case downscaling missed small distant faces
  detections = detector.Detect(frame, 0, 0.0, 1.0, 1.0);
  return detections;
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
  detector.Init(config.yunet_model_path, 0.38, 0.3);
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
  detector.Init(config.yunet_model_path, 0.38, 0.3);

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

const char* ClassroomGetLastError() { return g_last_error.c_str(); }

void ClassroomFreeString(const char* ptr) { delete[] ptr; }

}  // extern "C"
