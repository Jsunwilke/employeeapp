platform :ios, '16.0'
use_frameworks!

# Suppress all warnings from CocoaPods dependencies
inhibit_all_warnings!

target 'Iconik Employee' do
  # Firebase has been completely removed - using Supabase for all backend services
  # Push notifications use APNs directly via Supabase Edge Functions

  # NOTE: Supabase SDK uses Swift Package Manager, not CocoaPods
  # Add via Xcode: File > Add Package Dependencies
  # Repository: https://github.com/supabase/supabase-swift
  # Version: 2.0.0 or later

  # Add any other pods you need here...
end

# Post-install script for build configurations
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Set iOS deployment target to match the main app
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.6'

      # Suppress warnings
      config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      config.build_settings['SWIFT_SUPPRESS_WARNINGS'] = 'YES'
    end
  end

  # Update the pods project itself
  installer.pods_project.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.6'
  end
end