cmake_minimum_required(VERSION 3.20)
project(classroom_engine CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- OpenCV ---
# Uses the official prebuilt iOS framework (opencv2.framework) rather than
# building OpenCV from source ourselves, matching what opencv_dart/dartcv4
# ultimately builds too, but without repeating that ~5-minute CMake+source
# build — Apple's opencv.org release ships a ready framework directly.
#
# Pinned to 4.14.0, NOT the newer 5.0.0 — verified against the actual 5.0.0
# source tree that it removed CascadeClassifier/Haar Cascade from objdetect
# entirely. Using 4.x keeps this consistent with the Flutter/Dart branch,
# which uses OpenCV 4.x via opencv_dart and still has Haar Cascade.
# Download: https://github.com/opencv/opencv/releases/download/4.14.0/opencv-4.14.0-ios-framework.zip
# Expected to be unpacked at native/third_party/opencv2.framework
set(OPENCV_FRAMEWORK_DIR "${CMAKE_SOURCE_DIR}/third_party/opencv2.framework")

if(NOT EXISTS "${OPENCV_FRAMEWORK_DIR}")
  message(FATAL_ERROR
    "OpenCV iOS framework not found at ${OPENCV_FRAMEWORK_DIR}. "
    "Download and unzip opencv-4.14.0-ios-framework.zip from "
    "https://github.com/opencv/opencv/releases/tag/4.14.0 into native/third_party/ first."
  )
endif()

# --- ONNX Runtime ---
# Real iOS builds get this via CocoaPods (onnxruntime-c / onnxruntime-objc —
# the same package flutter_onnxruntime itself depends on) once this engine
# is embedded in the actual Xcode project — that pod resolution isn't
# CMake's job. For host-side dev/testing (this CMakeLists' actual current
# use — compiling and running the smoke tests locally on macOS), point
# ONNXRUNTIME_DIR at the downloaded onnxruntime-osx-arm64 package instead.
set(ONNXRUNTIME_DIR
    "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-osx-arm64-1.29.0"
    CACHE PATH "Path to an extracted ONNX Runtime distribution (headers + lib)")

if(NOT EXISTS "${ONNXRUNTIME_DIR}/include/onnxruntime_cxx_api.h")
  message(FATAL_ERROR
    "ONNX Runtime not found at ${ONNXRUNTIME_DIR}. For host-side testing, "
    "download onnxruntime-osx-arm64-*.tgz from "
    "https://github.com/microsoft/onnxruntime/releases into native/third_party/. "
    "For the real iOS build, override ONNXRUNTIME_DIR to point at the "
    "CocoaPods-resolved onnxruntime-c headers/lib instead."
  )
endif()

set(SOURCES
  src/frame_sampler.cpp
  src/blur_filter.cpp
  src/lighting_enhancer.cpp
  src/homography.cpp
  src/face_pose.cpp
  src/sahi_slicing.cpp
  src/desk_tracker.cpp
  src/yunet_detector.cpp
  src/haar_cascade_detector.cpp
  src/identity_clusterer.cpp
  src/roster_db.cpp
  src/cosine_matcher.cpp
  src/arcface_embedder.cpp
  src/retinaface_detector.cpp
  src/pipeline.cpp
)

find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
find_library(ONNXRUNTIME_LIBRARY
  NAMES onnxruntime
  PATHS "${ONNXRUNTIME_DIR}/lib"
  REQUIRED
  NO_DEFAULT_PATH
)

add_library(classroom_engine STATIC ${SOURCES})

target_include_directories(classroom_engine
  PUBLIC
    include
    ${ONNXRUNTIME_DIR}/include
)

# Framework-style include (#include <opencv2/opencv.hpp>) needs a framework
# search path (-F), not a plain header search path, since opencv2.framework
# resolves the opencv2/ prefix itself via Xcode's framework machinery.
# PUBLIC so both the compile flag (needed by anything including our headers)
# and the link flag (needed by anything linking classroom_engine, e.g. the
# smoketest executable, and later the Flutter iOS build) propagate to
# consumers — a static library itself has no link step, so target_link_options
# alone on this target wouldn't do anything without that propagation.
target_compile_options(classroom_engine PRIVATE -Wall -Wextra)
target_compile_options(classroom_engine PUBLIC -F${CMAKE_SOURCE_DIR}/third_party)
target_link_libraries(classroom_engine PUBLIC
  "-F${CMAKE_SOURCE_DIR}/third_party" "-framework opencv2"
  ${SQLITE3_LIBRARY}
  ${ONNXRUNTIME_LIBRARY}
)

# --- Tests ---
enable_testing()

add_executable(classroom_engine_smoketest test/smoketest.cpp)
target_link_libraries(classroom_engine_smoketest PRIVATE classroom_engine)

add_executable(classroom_engine_clustering_test test/clustering_test.cpp)
target_link_libraries(classroom_engine_clustering_test PRIVATE classroom_engine)

add_executable(classroom_engine_roster_test test/roster_test.cpp)
target_link_libraries(classroom_engine_roster_test PRIVATE classroom_engine)

# Self-contained — no CLI args or external fixtures needed — so these run
# directly under ctest.
add_test(NAME clustering_test COMMAND classroom_engine_clustering_test)
add_test(NAME roster_test COMMAND classroom_engine_roster_test)

# integration_test and pipeline_c_api_test need real model files (and, for
# integration_test, a real photo/video with a face) passed as CLI args — see
# each file's "Usage:" message. Built here so they're compile-checked on
# every run, but not auto-registered with ctest since there's no committed
# fixture image/video to point them at yet.
add_executable(classroom_engine_integration_test test/integration_test.cpp)
target_link_libraries(classroom_engine_integration_test PRIVATE classroom_engine)

add_executable(classroom_engine_pipeline_c_api_test test/pipeline_c_api_test.cpp)
target_link_libraries(classroom_engine_pipeline_c_api_test PRIVATE classroom_engine)
