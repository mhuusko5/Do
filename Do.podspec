Pod::Spec.new do |s|
  s.name = 'Do'
  s.version = '0.8.0'
  s.summary = 'A Swift-er way to do GCD-related things.'
  
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.authors = { 'Mathew Huusko V' => 'mhuusko5@gmail.com' }
  s.social_media_url = 'https://twitter.com/mhuusko5'
  
  s.homepage =         'https://github.com/mhuusko5/Do'
  s.source = { :git => 'https://github.com/mhuusko5/Do.git', :tag => s.version.to_s }

  s.requires_arc = true

  s.frameworks = 'Foundation'

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.9'
  
  s.subspec '1.2' do |ss|
    ss.source_files = 'Do-1.2.swift'
  end
  
  s.subspec '2.0' do |ss|
    ss.source_files = 'Do-2.0.swift'
  end
  
  s.default_subspecs = '2.0'
end
