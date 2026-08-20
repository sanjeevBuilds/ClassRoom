Pod::Spec.new do |s|
  s.name             = 'classroom_engine'
  s.version          = '0.0.1'
  s.summary          = 'ClassRoom on-device attendance pipeline (C++ engine, called via Dart FFI).'
  s.description      = 'Sampling, blur filtering, face detection, embedding, clustering and roster ' \
                        'matching, compiled as a local pod and linked into Runner. Not published; ' \
                        'consumed only by this app via :path.'
  s.homepage         = 'https://github.com/sanjeevBuilds/ClassRoom'
  s.license          = { :type => 'MIT' }
  s.author           = { 'ClassRoom' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '16.0'

  s.source_files     = 'src/*.cpp', 'include/classroom/*.h'
  s.public_header_files = 'include/classroom/pipeline.h'

  # Statically merged into Runner rather than a separate embedded dynamic
  # framework — Dart FFI reaches the extern "C" API via
  # DynamicLibrary.process(), which looks up symbols in the running
  # process's own image. That only works reliably if this code ends up
  # inside the main Runner binary, not a sibling .framework.
  s.static_framework = true

  # Prebuilt iOS framework (opencv-4.14.0-ios-framework.zip, unzipped here).
  # NOT committed to git (native/.gitignore) — see native/CMakeLists.txt's
  # comment for the download URL. Must exist on disk before `pod install`.
  s.vendored_frameworks = 'third_party/opencv2.framework'

  # Same onnxruntime-c version flutter_onnxruntime pins on the Dart branch —
  # already proven to install/link/run on this exact device.
  s.dependency 'onnxruntime-c', '1.23.0'

  s.libraries = 'sqlite3', 'c++'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/include" "$(PODS_ROOT)/onnxruntime-c/Headers"',
    'FRAMEWORK_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/third_party"',
    # Keep the extern "C" API's symbols exported even though nothing
    # Objective-C/Swift-side calls them — Dart FFI is the only caller,
    # via dlsym at runtime, invisible to the linker's usual reachability
    # analysis. See CLASSROOM_EXPORT in include/classroom/pipeline.h.
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
  }
end
