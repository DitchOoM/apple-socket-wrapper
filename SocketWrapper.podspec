#
# Be sure to run `pod lib lint SocketWrapper.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'SocketWrapper'
  s.version          = '0.1.0'
  s.summary          = 'An objective-c wrapper for NWConnection written in swift'
  s.swift_versions   = ['5.0']
  s.description      = <<-DESC
An objective-c wrapper for NWConnection written in swift. This is mainly used to expose NWConnection to kotlin.
                       DESC

  s.homepage         = 'https://github.com/DitchOoM/apple-socket-wrapper'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Rahul Behera' => 'rbehera@gmail.com' }
  s.source           = { :git => 'https://github.com/DitchOoM/apple-socket-wrapper.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'
  s.watchos.deployment_target = '6.0'
  s.tvos.deployment_target = '13.0'
  s.source_files = 'SocketWrapper/Classes/**/*'
  s.frameworks = 'Network'
end
