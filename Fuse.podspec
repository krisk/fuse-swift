Pod::Spec.new do |s|
  s.name             = 'Fuse'
  s.version          = '1.3.1'
  s.summary          = 'Fuzzy searching.'
  s.description      = <<-DESC
  A lightweight fuzzy-search library, with zero dependencies
  DESC

  s.homepage         = 'https://github.com/krisk/fuse-swift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Kirollos Risk' => 'kirollos@gmail.com' }
  s.source           = { :git => 'https://github.com/krisk/fuse-swift.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/kirorisk'

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.13'
  s.source_files = 'Fuse/Classes/**/*'
  s.swift_version = '5.0'
end
