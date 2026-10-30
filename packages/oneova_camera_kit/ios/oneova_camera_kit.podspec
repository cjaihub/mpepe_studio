Pod::Spec.new do |s|
  s.name             = 'oneova_camera_kit'
  s.version          = '0.1.0'
  s.summary          = 'Oneova Camera Kit: native Metal Look processing for Live and Camera.'
  s.description      = 'Grades flutter_webrtc local video frames with the Oneova Look shader on the GPU.'
  s.homepage         = 'https://oneova.app'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Oneova' => 'dev@oneova.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m,mm,swift}'
  s.public_header_files = 'Classes/OneovaWebRTCBridge.h'
  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'
  s.dependency 'WebRTC-SDK', '150.7871.01'
  s.platform         = :ios, '15.0'
  # Linked into the app once, like flutter_webrtc, so both share its singleton.
  s.static_framework = true
  s.frameworks       = 'Metal', 'CoreVideo', 'AVFoundation', 'VideoToolbox'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
