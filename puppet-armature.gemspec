# Ensure we require the local version and not one we might have installed already
require File.join([File.dirname(__FILE__),'lib','armature','version.rb'])
spec = Gem::Specification.new do |s|
  s.name = 'puppet-armature'
  s.version = Armature::VERSION
  s.author = 'Daniel Parks'
  s.email = 'os-armature@demonhorse.net'
  s.homepage = Armature::HOMEPAGE
  s.license = 'BSD-2-Clause'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Deploy Puppet environments and manage modules'
  s.description = <<-EOF
    Armature sets up Puppet environments for each branch in your control repo,
    then installs the modules specified in the Puppetfile for each environment.

    It is designed as a much faster replacement for r10k, though it does not
    have all of r10k's features.
  EOF
  s.files = `git ls-files`.split("\n") - [".gitignore"]
  s.require_paths << 'lib'
  s.has_rdoc = false
  s.bindir = 'bin'
  s.executables << 'armature'
  s.required_ruby_version = '>= 2.0.0'
  s.add_runtime_dependency('gli','2.14.0')
  s.add_runtime_dependency('logging','~> 2')
  s.add_development_dependency('minitest','~> 5.9')
  s.add_development_dependency('rake','<999')
end
