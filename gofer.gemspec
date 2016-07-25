# Ensure we require the local version and not one we might have installed already
require File.join([File.dirname(__FILE__),'lib','gofer','version.rb'])
spec = Gem::Specification.new do |s|
  s.name = 'gofer'
  s.version = Gofer::VERSION
  s.author = 'Daniel Parks'
  s.email = 'dp-gofer@oxidized.org'
  s.homepage = 'http://oxidized.org'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Tool to deploy Puppet environments and manage modules'
  s.files = `git ls-files`.split("\n")
  s.require_paths << 'lib'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.rdoc','gofer.rdoc']
  s.rdoc_options << '--title' << 'gofer' << '--main' << 'README.rdoc' << '-ri'
  s.bindir = 'bin'
  s.executables << 'gofer'
  s.add_development_dependency('rake')
  s.add_development_dependency('rdoc')
  s.add_development_dependency('aruba')
  s.add_runtime_dependency('gli','2.14.0')
  s.add_runtime_dependency('logging','~> 2')
end
