require 'fileutils'
require 'pathname'
require 'set'

module Gofer
  class Cache
    def initialize(path)
      @path = path
      @repos = {}
      @process_prefix = "#{Time.now.to_i}.#{Process.pid}"
      @sequence = 0
      @logger = Logging.logger[self]

      %w{repo sha tag branch object tmp}.each do |subdir|
        FileUtils.mkdir_p "#{@path}/#{subdir}"
      end
    end

    def get_repo(url)
      url_hash = self.class.fs_sanitize_url(url)

      repo_path = "#{@path}/repo/#{url_hash}"
      if ! Dir.exist? repo_path
        ### FIXME can we use --bare?
        # Ignore output
        @logger.info("Cloning '#{url}' for the first time")
        Gofer::Run.command("git", "clone", "--quiet", "--mirror", url, repo_path)
        @logger.debug("Done cloning '#{url}'")
      end

      get_repo_by_name(url_hash)
    end

    def get_repo_by_name(url_hash)
      @repos[url_hash] ||= GitRepo.new("#{@path}/repo/#{url_hash}", url_hash)
    end

    def checkout(repo, ref, options={})
      options = Gofer::Util.process_options(options, { :name=>nil })

      # Check cache first
      ["sha", "tag", "branch"].each do |type|
        ref_path = "#{@path}/#{type}/#{repo.name}/#{ref}"
        if Dir.exist? ref_path
          return ref_path
        end
      end

      # This will raise if the ref doesn't exist
      sha = repo.find_ref_sha(ref)
      if sha == ref
        type = "sha"
      else
        type = repo.ref_type(ref)
      end

      repo_dir = "#{@path}/#{type}/#{repo.name}"
      if ! Dir.exist? repo_dir
        Dir.mkdir(repo_dir)
      end

      ref_path = "#{repo_dir}/#{ref}"
      sha_path = checkout_sha(repo, sha, options[:name])
      if sha_path != ref_path
        atomic_symlink(sha_path, ref_path)
      end

      ref_path
    end

    def self.fs_sanitize_url(url)
      url.sub(/^\./, "%2e").gsub(" ", "%20").tr("/", " ")
    end

    # Creates a symlink atomically
    #
    # That is, if a symlink or file exists at new_path, then this will replace
    # it with the newly created symlink atomically.
    #
    # Both target_path and new_path should be absolute or relative to the
    # current working directory.
    def atomic_symlink(target_path, new_path)
      new_path.chomp!("/")

      @logger.debug("#{new_path} -> #{target_path}")

      real_new_dir = Pathname.new(new_path).dirname.realpath
      target_path = Pathname.new(target_path)

      if target_path.relative?
        # real_new_dir is absolute, so target_path must be as well for
        # relative_path_from() to work.
        target_path = Pathname.new(".").realpath + target_path
      end

      # Get target path relative to new_path
      target_path_from_new = target_path.relative_path_from(real_new_dir)

      temp_path = new_temp_path()
      File.symlink(target_path_from_new, temp_path)
      File.rename(temp_path, new_path)
    rescue
      @logger.error("Error in atomic_symlink('#{target_path}', '#{new_path}')")
      raise
    end

    def garbage_collect(code_path)
      ### FIXME lock

      def follow_path(path, referenced, visited=[])
        if not File.symlink? path
          raise "Expected a symlink: #{path}"
        end

        target = Pathname.new(File.join(
          File.dirname(path), File.readlink(path))).cleanpath.to_s

        if referenced.include? target
          # Short cut. We've already seen this path.
          return nil
        end

        visited << target

        if File.symlink? target
          if visited.size() >= 6
            raise "Symlink path more than 6 links deep: #{visited}"
          end

          return follow_path(target, referenced, visited)
        else
          ### Assume this is an object

          # Delay updating referenced until now so that we don't interfere with
          # loop detection. (Adding links as we find them would cause loops to
          # short circuit, resulting in a return of nil.)
          referenced.merge(visited)
          return target
        end
      end

      referenced_paths = Set.new
      env_objects = Set.new

      Dir.glob("#{code_path}/*") do |env_path|
        object_path = follow_path(env_path, referenced_paths)
        if object_path
          # We could get a nil if two branches evaluate to the same sha.
          env_objects << object_path

          Dir.glob("#{object_path}/modules/*") do |module_path|
            follow_path(module_path, referenced_paths)
          end
        end
      end

      all_references = Set.new(Dir.glob("#{@path}/{sha,tag,branch}/*/*"))
      difference = all_references - referenced_paths
      @logger.info("Deleting #{difference.size} of #{all_references.size} references")
      difference.each do |path|
        File.delete(path)
      end

      # Objects might take a while to delete, so move them into a
      # temporary directory and then delete them outside the lock.
      trash_path = new_temp_path()
      Dir.mkdir(trash_path)

      begin
        trash_sequence = 1

        all_objects = Set.new(Dir.glob("#{@path}/object/*"))
        difference = all_objects - referenced_paths
        @logger.info("Trashing #{difference.size} of #{all_objects.size} objects")
        difference.each do |path|
          File.rename(path, "#{trash_path}/#{trash_sequence}")
          trash_sequence += 1
        end

        ### GC repos
        ### remove excess modules directories

      ensure
        ### release lock
        @logger.info("Deleting trashed objects")
        FileUtils.remove_entry(trash_path)
        @logger.debug("Finished deleting trashed objects")
      end
    end

  private

    def new_temp_path
      @sequence += 1
      "#{@path}/tmp/#{@process_prefix}.#{@sequence}"
    end

    ### This should probably distribute objects among directories
    def new_object_path(name=nil)
      @sequence += 1
      if name
        name = "." + name.tr("/", " ")
      end

      "#{@path}/object/#{@process_prefix}.#{@sequence}#{name}"
    end

    # Assumes sha exists. Use checkout() if it might not.
    def checkout_sha(repo, sha, name=nil)
      repo_path = "#{@path}/sha/#{repo.name}"
      sha_path = "#{repo_path}/#{sha}"
      if Dir.exist? sha_path
        return sha_path
      end

      if ! Dir.exist? repo_path
        Dir.mkdir(repo_path)
      end

      object_path = new_object_path(name)
      FileUtils.mkdir_p object_path

      @logger.info(
        "Checking out '#{sha}' from '#{repo.url}' into '#{object_path}'")
      repo.git "reset", "--hard", sha, :work_dir=>object_path
      atomic_symlink(object_path, sha_path)

      sha_path
    end
  end
end
