require 'minitest/autorun'
require 'helpers'

class PuppetfileTest < Minitest::Test
  include ArmatureTestHelpers

  def test_empty
    with_temp_dir("puppetfile") do
      parse_puppetfile("")
    end
  end

  def test_one_module
    with_temp_dir("puppetfile") do
      results = parse_puppetfile(<<-PUPPETFILE)
        mod "interesting", :git=>"#{repo_path("foo")}"
      PUPPETFILE

      assert_equal(["interesting"], results.keys(),
        "Modules incorrect")
    end
  end

  def test_bad_module_name
    with_temp_dir("puppetfile") do
      assert_raises(Armature::Environments::InvalidNameError) do
        parse_puppetfile(<<-PUPPETFILE)
          mod "./foo", :git=>"#{repo_path("foo")}"
        PUPPETFILE
      end
    end
  end

private
  def parse_puppetfile(contents)
    @cache = Armature::Cache.new("cache")
    repo_init("foo")
    File.write("Puppetfile", contents)
    Armature::Puppetfile.new(@cache).include("Puppetfile")
  end
end
