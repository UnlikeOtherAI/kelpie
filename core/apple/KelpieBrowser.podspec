# Consume this source Pod from a pinned SDK checkout at core/apple.
Pod::Spec.new do |s|
  s.name = 'KelpieBrowser'
  s.version = '0.2.0'
  s.summary = 'The complete native Kelpie browser and its existing C++ core.'
  s.homepage = 'https://github.com/UnlikeOtherAI/kelpie'
  s.license = { :type => 'MIT', :file => '../../LICENSE' }
  s.author = 'UnlikeOtherAI'
  s.source = { :git => 'https://github.com/UnlikeOtherAI/kelpie.git' }
  s.platforms = { :ios => '16.0' }
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = ['ios/**/*.swift', 'shared/**/*.swift', 'Native/KelpieNative.h']
  s.private_header_files = 'Native/KelpieNative.h'
  s.preserve_paths = ['Native/module.modulemap', 'build-native.sh', 'build-pod-native.sh']
  s.resource_bundles = { 'KelpieBrowserResources' => ['../../assets/**/*', '../native/licenses/*'] }
  s.frameworks = ['UIKit', 'SwiftUI', 'WebKit', 'AppIntents', 'Accelerate']
  s.libraries = ['c++', 'KelpieNative']
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/../native/core-protocol/include"',
    'SWIFT_INCLUDE_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Native"'
  }
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "$(PODS_CONFIGURATION_BUILD_DIR)/KelpieBrowser/Native"'
  }
  root = File.expand_path('../..', __dir__)
  inputs = Dir["#{root}/core/native/{core-state,core-connect,core-protocol,core-automation,core-mcp,core-ai}/**/*.{cpp,cc,c,cxx,m,mm,h,hpp,cmake,txt}"]
  inputs += Dir["#{root}/packages/shared/**/*.{ts,json,mjs}"]
  inputs += ["#{root}/core/native/CMakeLists.txt", "#{root}/pnpm-lock.yaml", "#{root}/scripts/native/generate-browser-contract.mjs"]
  inputs += [File.join(__dir__, 'build-native.sh'), File.join(__dir__, 'build-pod-native.sh')]
  s.script_phase = {
    :name => 'Build Kelpie native core',
    :execution_position => :before_compile,
    :shell_path => '/bin/bash',
    :show_env_vars_in_log => false,
    :script => 'bash "$PODS_TARGET_SRCROOT/build-pod-native.sh"',
    :input_files => inputs,
    :output_files => ['$(PODS_CONFIGURATION_BUILD_DIR)/KelpieBrowser/Native/libKelpieNative.a']
  }
end
