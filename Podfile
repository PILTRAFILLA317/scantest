platform :ios, '17.0'

target 'ScanTest' do
  use_frameworks!

  pod 'StandardCyborgUI'
  pod 'StandardCyborgFusion'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end