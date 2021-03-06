require 'minitest/autorun'
require 'helpers'

class EnvironmentDeployTest < Minitest::Test
  include ArmatureTestHelpers

  def test_deploy_just_master_branch
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      branches = Set.new(repo.get_branches())

      assert_equal(Set.new(['master']), branches,
        "Branches before test incorrect")
      assert_equal([], @environments.names(),
        "Environments before test incorrect")

      @environments.check_out_ref(repo, "master")

      assert_equal(["master"], @environments.names(),
        "Environments after test incorrect")
      assert_equal(
        [".", "..", "master"].sort(),
        Dir.entries(@environments.path).sort(),
        "Environments directory after test incorrect")
    end
  end

  ### FIXME: should this generate an error?
  def test_deploy_nonexistant_branch
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      branches = Set.new(repo.get_branches())

      assert_equal(Set.new(['master']), branches,
        "Branches before test incorrect")

      @environments.check_out_ref(repo, "foo")

      assert_equal([], @environments.names(),
        "Environments after test incorrect")
    end
  end

  def test_deploy_all_branches
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      branches = Set.new(repo.get_branches())

      Dir.mkdir("foo")
      File.symlink("foo", @environments.path + "/foo")

      assert_equal(["foo"], @environments.names(),
        "Environments before test incorrect")

      (Set.new(@environments.names()) - branches).each do |name|
        @environments.remove(name)
      end

      branches.each do |branch|
        @environments.check_out_ref(repo, branch)
      end

      assert_equal(["master"], @environments.names(),
        "Environments after test incorrect")
    end
  end

  def test_deploy_one_module
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      @environments.check_out_ref(repo, "master")

      assert_equal(
        [".", "..", "module1"].sort(),
        Dir.entries(@environments.path + "/master/modules").sort(),
        "Modules installed after test incorrect")
    end
  end

  def test_adding_module_and_redeploying
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      @environments.check_out_ref(repo, "master")

      repo_init("module-2")
      repo_commit("control", "Add module-2") do
        File.write("Puppetfile", <<-PUPPETFILE)
          forge "https://forge.puppet.com"

          mod "module1", :git=>"#{repo_path('module-1')}"
          mod "module2", :git=>"#{repo_path('module-2')}"
        PUPPETFILE
      end

      @cache.flush_memory!
      @environments.check_out_ref(repo, "master")
      assert_equal(
        [".", "..", "module1", "module2"].sort(),
        Dir.entries(@environments.path + "/master/modules").sort(),
        "Modules installed after test incorrect")
      assert_environment_file_contains(
        "master/modules/module1/README.md",
        "# Armature test repo: module-1")
      assert_environment_file_contains(
        "master/modules/module2/README.md",
        "# Armature test repo: module-2")
    end
  end

  def test_removing_module_and_redeploying
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      @environments.check_out_ref(repo, "master")

      repo_commit("control", "Remove module-1") do
        File.write("Puppetfile", <<-PUPPETFILE)
          forge "https://forge.puppet.com"
        PUPPETFILE
      end

      @cache.flush_memory!
      @environments.check_out_ref(repo, "master")
      assert_equal(
        [".", ".."].sort(),
        Dir.entries(@environments.path + "/master/modules").sort(),
        "Modules installed after test incorrect")
    end
  end

  def test_module_with_bad_ref
    with_environment_context do
      repo_commit("control", "Set module-1 to bad ref") do
        File.write("Puppetfile", <<-PUPPETFILE)
          forge "https://forge.puppet.com"

          mod "module1", :git=>"#{repo_path('module-1')}", :ref=>"bad"
        PUPPETFILE
      end

      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      assert_raises(Armature::RefError) do
        @environments.check_out_ref(repo, "master")
      end

      ### FIXME state of repo after an error is undefined, but this behavior
      ### seems reasonable.
      assert_equal(
        [".", ".."].sort(),
        Dir.entries(@environments.path).sort(),
        "Modules installed after test incorrect")
    end
  end

  def test_redeploying_module_with_bad_ref
    with_environment_context do
      repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
      @environments.check_out_ref(repo, "master")

      repo_commit("control", "Set module-1 to bad ref") do
        File.write("Puppetfile", <<-PUPPETFILE)
          forge "https://forge.puppet.com"

          mod "module1", :git=>"#{repo_path('module-1')}", :ref=>"bad"
        PUPPETFILE
      end

      @cache.flush_memory!
      assert_raises(Armature::RefError) do
        @environments.check_out_ref(repo, "master")
      end

      ### What happens if other modules already exist?
      assert(! File.directory?(@environments.path + "/master/modules"),
        "Incorrectly created modules directory")
    end
  end

  def test_redeploying_module_with_ref_tag
    with_environment_context do
      set_up_interesting_module("interesting")
      redeploy_module_with_ref_of_type("ref", "tag_one") do
        assert_module_manifests("interesting", ["one.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_redeploying_module_with_ref_branch
    with_environment_context do
      set_up_interesting_module("interesting")
      redeploy_module_with_ref_of_type("ref", "branch_two") do
        assert_module_manifests("interesting", ["one.pp", "two.pp", "two_a.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_redeploying_module_with_ref_commit
    with_environment_context do
      set_up_interesting_module("interesting")
      sha = repo_git("interesting", "rev-parse", "branch_two^").chomp
      redeploy_module_with_ref_of_type("ref", sha) do
        assert_module_manifests("interesting", ["one.pp", "two.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_redeploying_module_with_tag
    with_environment_context do
      set_up_interesting_module("interesting")
      redeploy_module_with_ref_of_type("tag", "tag_one") do
        assert_module_manifests("interesting", ["one.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_redeploying_module_with_branch
    with_environment_context do
      set_up_interesting_module("interesting")
      redeploy_module_with_ref_of_type("branch", "branch_two") do
        assert_module_manifests("interesting", ["one.pp", "two.pp", "two_a.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_redeploying_module_with_commit
    with_environment_context do
      set_up_interesting_module("interesting")
      sha = repo_git("interesting", "rev-parse", "branch_two^").chomp
      redeploy_module_with_ref_of_type("commit", sha) do
        assert_module_manifests("interesting", ["one.pp", "two.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_redeploying_module_with_updated_branch
    with_environment_context do
      set_up_interesting_module("interesting")
      redeploy_module_with_ref_of_type("ref", "branch_two") do
        repo_git("interesting", "checkout", "branch_two")
        add_module_class("interesting", "two_b")

        @cache.flush_memory!
        @environments.check_out_ref(Armature::Repo::Git::from_url(@cache, repo_path("control")), "master")

        assert_module_manifests("interesting",
          ["one.pp", "two.pp", "two_a.pp", "two_b.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

  def test_updating_branches_on_module_with_updated_branch
    with_environment_context do
      set_up_interesting_module("interesting")
      redeploy_module_with_ref_of_type("ref", "branch_two") do
        repo_git("interesting", "checkout", "branch_two")
        add_module_class("interesting", "two_b")

        @cache.flush_memory!
        @cache.update_mutable_refs()

        assert_module_manifests("interesting",
          ["one.pp", "two.pp", "two_a.pp", "two_b.pp"],
          "Incorrect module version after redeploy")
      end
    end
  end

private

  # The "interesting" repo must be created first so it can be queried for shas
  def redeploy_module_with_ref_of_type(ref_type, ref)
    repo_puppetfile_update("control", <<-MODULES)
      mod "interesting", :git=>"#{repo_path('interesting')}"
    MODULES

    control_repo = Armature::Repo::Git::from_url(@cache, repo_path("control"))
    @environments.check_out_ref(control_repo, "master")

    assert_module_manifests("interesting", ["one.pp", "two.pp", "three.pp"],
      "Incorrect module version after initial deploy")

    repo_commit("control", "Add interesting module") do
      File.write("Puppetfile", <<-PUPPETFILE)
        forge "https://forge.puppet.com"

        mod "interesting", :git=>"#{repo_path('interesting')}",
          :#{ref_type}=>"#{ref}"
      PUPPETFILE
    end

    @cache.flush_memory!
    @environments.check_out_ref(control_repo, "master")

    yield
  end
end
