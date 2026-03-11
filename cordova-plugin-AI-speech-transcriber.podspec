Pod::Spec.new do |s|
  s.name             = 'cordova-plugin-AI-speech-transcriber'
  s.version          = '1.1.1'
  s.summary          = '基于阿里云SDK的Cordova语音转写和语音合成插件'
  s.description      = <<-DESC
    基于阿里云SDK的Cordova语音转写和语音合成插件，支持实时语音转写和语音合成功能。
  DESC
  s.homepage         = 'https://github.com/CTY-Library/cordova-plugin-AI-speech-transcriber'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'CTY-Library' => 'cty-library@example.com' }
  s.source           = { :git => 'https://github.com/CTY-Library/cordova-plugin-AI-speech-transcriber.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.source_files = 'src/ios/**/*.{h,m,mm}'
  s.public_header_files = 'src/ios/**/*.h'
  
  # 框架依赖
  s.frameworks = 'AVFoundation', 'CoreAudio', 'AudioToolbox', 'SystemConfiguration', 'CoreTelephony'
  s.libraries = 'z', 'c++'
  
  # 自定义framework
  s.vendored_frameworks = 'src/ios/lib/nuisdk.framework'
  
  # 资源文件
  s.resource_bundles = {
    'cordova-plugin-AI-speech-transcriber' => ['src/ios/lib/nuisdk.framework/Resources.bundle']
  }
  
  # 编译设置
  s.xcconfig = {
    'OTHER_LDFLAGS' => '-framework nuisdk',
    'ENABLE_BITCODE' => 'NO'
  }
  
  # 排除架构
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
end
