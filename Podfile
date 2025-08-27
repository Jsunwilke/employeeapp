platform :ios, '16.0'
use_frameworks!

target 'Iconik Employee' do
  # Firebase pods
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'
  pod 'FirebaseFirestoreSwift'
  pod 'Firebase/Storage'
  pod 'Firebase/Messaging'
  pod 'Firebase/Core'
  pod 'Firebase/Analytics'
  pod 'Firebase/Functions'
  pod 'GoogleSignIn'
  pod 'GoogleAPIClientForREST/Drive'
  pod 'GoogleAPIClientForREST/Sheets'
  
  # Stream Chat
  pod 'StreamChat', '~> 4.50.0'
  pod 'StreamChatUI', '~> 4.50.0'
  
  # Add any other pods you need here...
end

# Post-install script to handle build configurations
post_install do |installer|
  installer.pods_project.targets.each do |target|
    # Handle BoringSSL-GRPC flags
    if target.name == 'BoringSSL-GRPC'
      target.source_build_phase.files.each do |file|
        if file.settings && file.settings['COMPILER_FLAGS']
          flags = file.settings['COMPILER_FLAGS'].split
          # Remove any flags containing '-G'
          flags.reject! { |flag| flag.include?('-G') }
          file.settings['COMPILER_FLAGS'] = flags.join(' ')
        end
      end
    end
    
    # Set C++ language standard to gnu++17 for all pods
    target.build_configurations.each do |config|
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++17'
      config.build_settings['CMAKE_CXX_STANDARD'] = '17'
      # Set iOS deployment target to match the main app
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.6'
    end
  end
  
  # Also update the pods project itself
  installer.pods_project.build_configurations.each do |config|
    config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++17'
    config.build_settings['CMAKE_CXX_STANDARD'] = '17'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.6'
  end
  
  # Fix gRPC-Core xcconfig files to use C++17 instead of C++14
  grpc_core_xcconfigs = [
    "Pods/Target Support Files/gRPC-Core/gRPC-Core.debug.xcconfig",
    "Pods/Target Support Files/gRPC-Core/gRPC-Core.release.xcconfig",
    "Pods/Target Support Files/gRPC-C++/gRPC-C++.debug.xcconfig",
    "Pods/Target Support Files/gRPC-C++/gRPC-C++.release.xcconfig"
  ]
  
  grpc_core_xcconfigs.each do |xcconfig_path|
    if File.exist?(xcconfig_path)
      config_content = File.read(xcconfig_path)
      # Replace C++14 with gnu++17
      config_content.gsub!(/CLANG_CXX_LANGUAGE_STANDARD = c\+\+14/, 'CLANG_CXX_LANGUAGE_STANDARD = gnu++17')
      # Also update any CMAKE settings
      config_content.gsub!(/CMAKE_CXX_STANDARD = 14/, 'CMAKE_CXX_STANDARD = 17')
      File.write(xcconfig_path, config_content)
      puts "Updated #{xcconfig_path} to use C++17"
    end
  end
  
  # Also fix abseil xcconfig files if they exist
  abseil_xcconfigs = [
    "Pods/Target Support Files/abseil/abseil.debug.xcconfig",
    "Pods/Target Support Files/abseil/abseil.release.xcconfig"
  ]
  
  abseil_xcconfigs.each do |xcconfig_path|
    if File.exist?(xcconfig_path)
      config_content = File.read(xcconfig_path)
      config_content.gsub!(/CLANG_CXX_LANGUAGE_STANDARD = c\+\+14/, 'CLANG_CXX_LANGUAGE_STANDARD = gnu++17')
      config_content.gsub!(/CMAKE_CXX_STANDARD = 14/, 'CMAKE_CXX_STANDARD = 17')
      File.write(xcconfig_path, config_content)
      puts "Updated #{xcconfig_path} to use C++17"
    end
  end
  
  # Fix gRPC template syntax issue for Xcode 16 compatibility
  grpc_basic_seq_path = "Pods/gRPC-Core/src/core/lib/promise/detail/basic_seq.h"
  if File.exist?(grpc_basic_seq_path)
    content = File.read(grpc_basic_seq_path)
    # Fix template syntax by adding empty template brackets
    if content.include?("Traits::template CallSeqFactory(")
      content.gsub!("Traits::template CallSeqFactory(", "Traits::template CallSeqFactory<>(")
      File.write(grpc_basic_seq_path, content)
      puts "Fixed gRPC template syntax in #{grpc_basic_seq_path}"
    end
  end
  
  # Also check gRPC-C++ directory
  grpc_cpp_basic_seq_path = "Pods/gRPC-C++/src/core/lib/promise/detail/basic_seq.h"
  if File.exist?(grpc_cpp_basic_seq_path)
    content = File.read(grpc_cpp_basic_seq_path)
    if content.include?("Traits::template CallSeqFactory(")
      content.gsub!("Traits::template CallSeqFactory(", "Traits::template CallSeqFactory<>(")
      File.write(grpc_cpp_basic_seq_path, content)
      puts "Fixed gRPC template syntax in #{grpc_cpp_basic_seq_path}"
    end
  end
end