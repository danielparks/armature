require 'armature'
require 'fileutils'
require 'tmpdir'

module ArmatureTestHelpers
  def repo_path(name)
    @context_path + "/repos/" + name
  end

  def repo_init(name)
    Armature::Run.clean_git("init", repo_path(name))
    repo_commit(name, "Initial revision of #{name}") do
      File.write("README.md", <<-README)
        # Armature test repo: #{name}

        Located at #{repo_path(name)}
      README

      Dir.mkdir("manifests")
      File.write("manifests/.keep", "")

      if block_given?
        yield
      end
    end
  end

  def repo_commit(name, message)
    Dir.chdir(repo_path(name)) do
      yield
      Armature::Run.clean_git("add", ".")
      Armature::Run.clean_git("commit", "-m", message)
    end
  end

  def repo_git(name, *command)
    Dir.chdir(repo_path(name)) do
      Armature::Run.clean_git(*command)
    end
  end

  def repo_puppetfile_update(name, modules)
    repo_commit(name, "Update Puppetfile") do
      File.write("Puppetfile", <<-PUPPETFILE)
        forge "https://forge.puppet.com"

        #{modules}
      PUPPETFILE
    end
  end

  def add_module_class(module_name, class_name)
    repo_commit(module_name, "Add #{class_name}.pp") do
      File.write("manifests/#{class_name}.pp", <<-MANIFEST)
        class module1::#{class_name} {
          notify { "in #{module_name}::#{class_name}": }
        }
      MANIFEST
    end
  end

  def set_up_interesting_module(module_name)
    repo_init(module_name)

    add_module_class(module_name, "one")
    repo_git(module_name, "tag", "tag_one")
    add_module_class(module_name, "two")
    repo_git(module_name, "checkout", "-b", "branch_two")
    add_module_class(module_name, "two_a")
    repo_git(module_name, "checkout", "master")
    add_module_class(module_name, "three")
  end

  def set_up_context
    @context_path = Dir.mktmpdir("armature.test_context.")
    @cache = Armature::Cache.new(@context_path + "/cache")

    Dir.mkdir(@context_path + "/environments")
    @environments = Armature::Environments.new(@context_path + "/environments", @cache)

    repo_init("module-1")

    repo_init("control") do
      File.write("Puppetfile", <<-PUPPETFILE)
        forge "https://forge.puppet.com"

        mod "module1", :git=>"#{repo_path('module-1')}"
      PUPPETFILE
    end
  end

  def tear_down_context
    FileUtils.rm_rf(@context_path)

    # Ensure that code trying to use these after this point fails in a
    # predictable way.
    @context_path = nil
    @cache = nil
    @environments = nil
  end

  def with_context
    set_up_context
    yield
    tear_down_context
  end

  def environment_file_contains?(path, search)
    File.foreach(@environments.path + "/" + path).any? do
      |line| line.include? search
    end
  end

  def assert_environment_file_contains(path, search, message=nil)
    if ! message
      message = "#{path} does not contain '#{search}'"
    end

    assert(environment_file_contains?(path, search), message)
  end

  def assert_module_manifests(module_name, manifest_names=["init.pp"],
      message="Incorrect manifests in module '#{module_name}'",
      environment="master")
    assert_equal(
      ([".", "..", ".keep"] + manifest_names).sort(),
      Dir.entries(@environments.path + "/#{environment}/modules/#{module_name}/manifests"),
      message)
  end
end
