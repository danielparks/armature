require 'armature'
require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'

class DeployTest < Minitest::Test
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

  def test_deploy_just_master_branch
    with_context do
      repo = @cache.get_repo(repo_path("control"))
      branches = Set.new(repo.get_branches())

      assert_equal(Set.new(['master']), branches,
        "Branches before test incorrect")
      assert_equal([], @environments.names(),
        "Environments before test incorrect")

      @environments.checkout_ref(repo, "master")

      assert_equal(["master"], @environments.names(),
        "Environments after test incorrect")
      assert_equal([".", "..", "master"], Dir.entries(@environments.path),
        "Environments directory after test incorrect")
    end
  end

  ### FIXME: should this generate an error?
  def test_deploy_nonexistant_branch
    with_context do
      repo = @cache.get_repo(repo_path("control"))
      branches = Set.new(repo.get_branches())

      assert_equal(Set.new(['master']), branches,
        "Branches before test incorrect")

      @environments.checkout_ref(repo, "foo")

      assert_equal([], @environments.names(),
        "Environments after test incorrect")
    end
  end

  def test_deploy_all_branches
    with_context do
      repo = @cache.get_repo(repo_path("control"))
      branches = Set.new(repo.get_branches())

      Dir.mkdir(@context_path + "/foo")
      File.symlink(@context_path + "/foo", @environments.path + "/foo")

      assert_equal(["foo"], @environments.names(),
        "Environments before test incorrect")

      (Set.new(@environments.names()) - branches).each do |name|
        @environments.remove(name)
      end

      branches.each do |branch|
        @environments.checkout_ref(repo, branch)
      end

      assert_equal(["master"], @environments.names(),
        "Environments after test incorrect")
    end
  end

  def test_deploy_one_module
    with_context do
      repo = @cache.get_repo(repo_path("control"))
      @environments.checkout_ref(repo, "master")

      assert_equal(
        [".", "..", "module1"],
        Dir.entries(@environments.path + "/master/modules"),
        "Modules installed after test incorrect")
    end
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

  def test_adding_module_and_redeploying
    with_context do
      repo = @cache.get_repo(repo_path("control"))
      @environments.checkout_ref(repo, "master")

      repo_init("module-2")
      repo_commit("control", "Add module-2") do
        File.write("Puppetfile", <<-PUPPETFILE)
          forge "https://forge.puppet.com"

          mod "module1", :git=>"#{repo_path('module-1')}"
          mod "module2", :git=>"#{repo_path('module-2')}"
        PUPPETFILE
      end

      @cache.flush_memory!
      @environments.checkout_ref(repo, "master")
      assert_equal(
        [".", "..", "module1", "module2"],
        Dir.entries(@environments.path + "/master/modules"),
        "Modules installed after test incorrect")
      assert_environment_file_contains(
        "master/modules/module1/README.md",
        "# Armature test repo: module-1")
      assert_environment_file_contains(
        "master/modules/module2/README.md",
        "# Armature test repo: module-2")
    end
  end
end
