Pod::Spec.new do |s|
  s.name             = 'fwhisper'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter FFI plugin for Whisper.'
  s.description      = <<-DESC
                       A Flutter FFI plugin project named Whisper, designed to facilitate easy integration of the Whisper library into Flutter applications.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*', 'whisper.cpp/{ggml.c,ggml-quants.c,ggml-backend.c,ggml-alloc.c,ggml-metal.m}'
  s.exclude_files    = 'bindings', 'cmake', 'coreml', 'examples', 'extra', 'models', 'samples', 'tests', 'CMakeLists.txt', 'ggml-cuda.cu', 'ggml-cuda.h', 'Makefile'
  s.frameworks       = 'Foundation', 'Metal', 'MetalKit', 'Accelerate'
  s.dependency       'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_CFLAGS' => ['$(inherited)', '-Wno-shorten-64-to-32', '-O3', '-flto', '-fno-objc-arc'],
    'OTHER_CPLUSPLUSFLAGS' => ['$(inherited)', '-Wno-shorten-64-to-32', '-O3', '-flto', '-fno-objc-arc'],
    'GCC_PREPROCESSOR_DEFINITIONS' => ['$(inherited)', 'GGML_USE_METAL=1'],
  }
  s.swift_version    = '5.0'
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
xcrun metal -target air64-apple-macosx -ffast-math -std=macos-metal2.3 -o "${METAL_LIBRARY_OUTPUT_DIR}/default.metallib" *.metal
SCRIPT
    }
  ]
end
