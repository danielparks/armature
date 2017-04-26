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
end
