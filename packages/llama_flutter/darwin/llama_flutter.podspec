#
# Shared iOS + macOS podspec (sharedDarwinSource).
# The vendored llama.xcframework is produced by
# scripts/build_llama_xcframework.sh and is NOT checked into source control.
#
Pod::Spec.new do |s|
  s.name             = 'llama_flutter'
  s.version          = '0.1.0'
  s.summary          = 'On-device llama.cpp inference for iOS and macOS.'
  s.description      = <<-DESC
  Flutter plugin wrapping llama.cpp via a vendored xcframework, exposed through
  a Pigeon bridge with a streaming token EventChannel.
                       DESC
  s.homepage         = 'https://example.com/llama_flutter'
  s.license          = { :type => 'MIT', :text => 'See LICENSE in repo root.' }
  s.author           = { 'llama_flutter' => 'dev@example.com' }
  s.source           = { :path => '.' }

  # Build the plugin as a static framework so the dynamic llama.framework it
  # vendors is linked + embedded by the final app target (which carries
  # `-framework llama`), rather than by this pod's own dynamic-framework link.
  s.static_framework    = true

  s.source_files        = 'Classes/**/*'
  s.vendored_frameworks = 'Frameworks/llama.xcframework'
  s.preserve_paths      = 'Frameworks/llama.xcframework'
  s.frameworks          = 'Metal', 'MetalKit', 'Accelerate', 'Foundation'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '16.4'
  s.osx.deployment_target = '13.3'

  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
  }
end
