#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fwhisper.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fwhisper'
  s.version          = '1.0.0'
  s.summary          = 'A new Flutter FFI plugin project. Whisper'
  s.description      = <<-DESC
A new Flutter FFI plugin project Whisper.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*',
                        'whisper.cpp/ggml.c', 
                        'whisper.cpp/ggml-quants.c', 
                        'whisper.cpp/ggml-backend.c', 
                        'whisper.cpp/ggml-alloc.c',
                        'whisper.cpp/ggml-metal.m'
  s.frameworks = 'Foundation', 'Metal', 'MetalKit'
  s.dependency 'Flutter'
  # s.vendored_libraries = 'Frameworks/libfwhisper.dylib', 'Frameworks/libwhisper.dylib'

  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'USER_HEADER_SEARCH_PATHS' => ['$(PODS_TARGET_SRCROOT)/../whisper.cpp/**/*.h', '$(PODS_TARGET_SRCROOT)/../whisper.cpp/common/**/*.h'],
  'OTHER_CFLAGS' => ['$(inherited)', '-O3', '-flto', '-fno-objc-arc'],
  'OTHER_CPLUSPLUSFLAGS' => ['$(inherited)', '-O3', '-flto', '-fno-objc-arc'],
  'GCC_PREPROCESSOR_DEFINITIONS' => ['$(inherited)', 'GGML_USE_METAL=1'],
  }
  s.swift_version = '5.0'

  s.script_phases = [
    {
      :name => 'Build Metal Library',
      :input_files => ["${PODS_TARGET_SRCROOT}/whisper.cpp/ggml-metal.metal"],
      :output_files => ["${METAL_LIBRARY_OUTPUT_DIR}/default.metallib"],
      :execution_position => :after_compile,
      :script => <<-SCRIPT
set -e
set -u
set -o pipefail
echo "METAL_LIBRARY_OUTPUT_DIR is set to ${METAL_LIBRARY_OUTPUT_DIR}"
cd "${PODS_TARGET_SRCROOT}/whisper.cpp"
xcrun metal -target "air64-${LLVM_TARGET_TRIPLE_VENDOR}-${LLVM_TARGET_TRIPLE_OS_VERSION}${LLVM_TARGET_TRIPLE_SUFFIX:-\"\"}" -ffast-math -std=ios-metal2.3 -o "${METAL_LIBRARY_OUTPUT_DIR}/default.metallib" *.metal
SCRIPT
    }
  ]
end
