require 'rubygems/package_task'
require 'rake/testtask'

# Build packages from all .gemspec files
FileList['*.gemspec'].each do |path|
  Gem::PackageTask.new(eval(File.read(path))) { |pkg| }
end

Rake::TestTask.new do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList['test/*_test.rb']
end
