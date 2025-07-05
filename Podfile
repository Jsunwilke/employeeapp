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
  
  # Add any other pods you need here...
end

# Post-install script to remove '-G' flags from BoringSSL-GRPC
post_install do |installer|
  installer.pods_project.targets.each do |target|
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
  end
end