require "json"
require "net/http"
require "uri"

# Get a module from the Forge
class Armature::Repo::Forge < Armature::Repo
  CANONICAL_FORGE_URL = "https://forge.puppet.com"
  FORGE_URLS = [
    "https://forge.puppetlabs.com",
    "https://forgeapi.puppetlabs.com",
    "https://forgeapi.puppet.com",
    "http://forge.puppetlabs.com",
    "http://forgeapi.puppetlabs.com",
    "http://forge.puppet.com",
    "http://forgeapi.puppet.com",
  ]

  def self.normalize_forge_url(url)
    url.chomp!("/")
    if FORGE_URLS.include? url
      CANONICAL_FORGE_URL
    else
      url
    end
  end

  # Gets a repo object for a given Forge module. This just contains metadata.
  def self.from_url(cache, forge_url, full_name)
    forge_url = self.normalize_forge_url(forge_url)

    url = "#{forge_url}/#{full_name}"
    repo = cache.get_repo("forge", url)
    if repo
      return repo
    end

    repo_dir = cache.open_repo("forge", url) do |temp_path|
      File.write("#{temp_path}/url", "#{url}\n")
      File.write("#{temp_path}/forge_url", "#{forge_url}\n")
      File.write("#{temp_path}/full_name", "#{full_name}\n")

      Logging.logger[self].debug("Created stub repo for '#{url}'")
    end

    return self.new(cache, repo_dir)
  end

  def url
    @url || File.read("#{@repo_dir}/url").chomp()
  end

  def forge_url
    @forge_url || File.read("#{@repo_dir}/forge_url").chomp()
  end

  def full_name
    @full_name || File.read("#{@repo_dir}/full_name").chomp()
  end

  # Ensure we've got the correct version and return its path
  def check_out(ref)
    @cache.open_ref(ref) do |object_path|
      @cache.open_temp() do
        @logger.debug("Downloading #{ref} from #{url}")
        url = forge_url() + release_metadata(ref.identity, "file_uri")

        tarball = Armature::Util::http_get(url)

        # This extracts into a temp directory
        Armature::Run::pipe_command(tarball, "tar", "xzf" , "-")

        # Move everything into the object directory
        extract_dir = Dir["*"].first()
        Dir.entries(extract_dir).each do |child|
          if ! [".", ".."].include?(child)
            File.rename("#{extract_dir}/#{child}", "#{object_path}/#{child}")
          end
        end
      end
    end
  end

  def freshen!
    flush_memory!
    download_metadata()
  end

  def flush_memory!
    @fresh = false
    @metadata = nil
  end

  # Get ref object
  def general_ref(version)
    if version.nil? || version == "latest"
      latest_ref()
    else
      version_ref(version)
    end
  end

  def version_ref(version)
    Armature::Ref::Immutable.new(self, version, version, "version", version)
  end

  def latest_ref
    freshen()
    version = metadata("current_release.version")

    Armature::Ref::Mutable.new(self, "latest", version, "version", "latest")
  end

private

  def metadata(path=nil)
    ### FIXME cache metadata in repo
    @metadata ||= download_metadata()
    return @metadata if path == nil

    begin
      dig(@metadata, path.split("."))
    rescue => e
      raise "Got invalid metadata from #{metadata_url()}: #{e}"
    end
  end

  def release_metadata(version, path=nil)
    metadata("releases").each do |release|
      begin
        if release["version"] == version
          return dig(release, path.split("."))
        end
      rescue => e
        raise "Got invalid metadata from #{metadata_url()}: #{e}"
      end
    end

    raise "Release #{version} not found"
  end

  def metadata_url
    [forge_url(), "v3", "modules", full_name()].join("/")
  end

  def download_metadata
    @fresh = true
    @metadata = Armature::Util::http_get_json(metadata_url())
  end

  def dig(parent, path)
    key = path.shift()
    if path.length() == 0
      parent[key]
    else
      dig(parent[key], path)
    end
  end
end
