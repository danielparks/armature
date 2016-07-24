require 'digest'
require 'fileutils'

module Gofer
  class Cache
    ### FIXME garbage_collect not implemented
    def initialize(path)
      @path = path
      @sequence = 0

      %w{repo sha tag branch object tmp}.each do |subdir|
        FileUtils.mkdir_p "#{@path}/#{subdir}"
      end
    end

    def get_repo(url)
      url_hash = self.class.hash_url(url)
      repo_path = "#{@path}/repo/#{url_hash}"

      if ! Dir.exist? repo_path
        ### FIXME can we use --bare?
        # Ignore output
        Gofer::Run.command("git", "clone", "--quiet", "--mirror", url, repo_path)
      end

      GitRepo.new(url_hash, repo_path)
    end

    def get_ref_path(repo, ref)
      cached_ref(repo, ref) do |ref_path|
        sha = repo.ref_sha(ref)
        sha_path = self.get_sha_path(repo, sha)
        if sha_path != ref_path
          self.atomic_symlink(sha_path, ref_path)
        end
      end
    end

    def self.hash_url(url)
      ### something more human readable would be nice
      Digest::MD5.hexdigest(url)
    end

    def atomic_symlink(target_path, new_path)
      temp_path = self.new_temp_path()
      File.symlink(target_path, temp_path)
      File.rename(temp_path, new_path)
    end

  private

    def new_temp_path
      @sequence += 1
      "#{@path}/tmp/#{Time.now.to_i}.#{Process.pid}.#{@sequence}"
    end

    def new_object_path
      @sequence += 1
      "#{@path}/object/#{Time.now.to_i}.#{Process.pid}.#{@sequence}"
    end

    ### FIXME better name
    ### Check if a ref has been cached, otherwise yield the path to stick the object in
    def cached_ref(repo, ref)
      type = repo.ref_type(ref).to_s

      repo_dir = "#{@path}/#{type}/#{repo.name}"
      ref_path = "#{repo_dir}/#{ref}"
      if Dir.exist? ref_path
        return ref_path
      end

      if Dir.exist? repo_dir
        Dir.mkdir(repo_dir)
      end

      yield ref_path
      ref_path
    end

    # Assumes sha exists. Use get_ref_path if it might not.
    def get_sha_path(repo, ref)
      cached_ref(repo, ref) do |sha_path|
        object_path = self.new_object_path()
        FileUtils.mkdir_p object_path
        repo.git "checkout", sha, :work_dir=>object_path

        self.atomic_symlink(object_path, sha_path)
      end
    end
  end
end
