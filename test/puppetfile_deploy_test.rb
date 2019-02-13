require 'minitest/autorun'
require 'helpers'

class PuppetfileDeployTest < Minitest::Test
  include ArmatureTestHelpers

  def test_deploy_puppetfile
    with_control do
			@cache.lock File::LOCK_SH do
				puppetfile = Armature::Puppetfile.new(@cache)
				success = puppetfile.load_control_directory("control")
				assert(success, "Failed to load control/Puppetfile")

				puppetfile.update_modules("control")
			end

      assert(File.directory?("control/modules"),
        "Failed to create control/modules")
      assert_equal(
        [".", "..", "module1"].sort(),
        Dir.entries("control/modules").sort(),
        "Installed modules incorrectly")
    end
  end

  def test_deploy_nonexistent_puppetfile
    with_context do
    	Dir.mkdir("control")

			@cache.lock File::LOCK_SH do
				puppetfile = Armature::Puppetfile.new(@cache)
				success = puppetfile.load_control_directory("control")
				assert(!success, "Loaded non-existent Puppetfile")
			end

      assert(! File.directory?("control/modules"),
        "Incorrectly created control/modules")
    end
  end

  def test_deploy_puppetfile_moduledir
    with_control do
			File.write("control/Puppetfile", <<-PUPPETFILE)
				forge "https://forge.puppet.com"
				moduledir "vendor"

				mod "module1", :git=>"#{repo_path('module-1')}"
			PUPPETFILE

			@cache.lock File::LOCK_SH do
				puppetfile = Armature::Puppetfile.new(@cache)
				success = puppetfile.load_control_directory("control")
				assert(success, "Failed to load control/Puppetfile")

				puppetfile.update_modules("control")
			end

      assert(! File.directory?("control/modules"),
        "Incorrectly created control/modules")
      assert(File.directory?("control/vendor"),
        "Failed to create control/vendor")
      assert_equal(
        [".", "..", "module1"].sort(),
        Dir.entries("control/vendor").sort(),
        "Installed modules incorrectly")
    end
  end

private

  def with_control
    with_context do
    	Dir.mkdir("control")
			File.write("control/Puppetfile", <<-PUPPETFILE)
				forge "https://forge.puppet.com"

				mod "module1", :git=>"#{repo_path('module-1')}"
			PUPPETFILE

			yield
    end
  end
end
