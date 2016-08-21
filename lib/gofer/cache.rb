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

    # Get GitRepo object for a local clone of a remote repo at a URL
    #
    # This will clone the repo if it doesn't already exist.
    def get_repo(url)
      safe_url = fs_sanitize(url)

      repo_path = "#{@path}/repo/#{safe_url}"
      if ! Dir.exist? repo_path
        @logger.info("Cloning '#{url}' for the first time")
        Gofer::Util::lock repo_path, File::LOCK_EX, "clone" do
          if Dir.exist? repo_path
            @logger.info("Another process cloned '#{url}' while we were blocked")
          else
            # Ignore output
            Gofer::Run.command("git", "clone", "--quiet", "--bare", url, repo_path)
            @logger.debug("Done cloning '#{url}'")
          end
        end
      end

      get_repo_by_name(safe_url)
    end

    # Get a GitRepo object for an existing local repo by its santized URL
    def get_repo_by_name(safe_url)
      @repos[safe_url] ||= GitRepo.new("#{@path}/repo/#{safe_url}", safe_url)
    end

    # Check out a ref from a repo and return the path
    def checkout(repo, ref, options={})
      options = Gofer::Util.process_options(options,
        { :name=>nil }, { :refresh=>false })

      safe_ref = fs_sanitize(ref)

      if options[:refresh]
        # Don't check the cache; refresh it from source.
        repo.freshen()
      else
        # Check cache first
        ["sha", "tag", "branch"].each do |type|
          ref_path = "#{@path}/#{type}/#{repo.name}/#{safe_ref}"
          if Dir.exist? ref_path
            return ref_path
          end
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

      ref_path = "#{repo_dir}/#{safe_ref}"
      sha_path = checkout_sha(repo, sha, options[:name])
      if sha_path != ref_path
        atomic_symlink(sha_path, ref_path)
      end

      ref_path
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

    def update_branches()
      Dir.glob("#{@path}/branch/*/*") do |path|
        branch = File.basename(path)
        repo = get_repo_by_name(File.basename(File.dirname(path)))
        @logger.info("Updating #{branch} branch from #{repo.url}")

        begin
          checkout(repo, branch, :refresh=>true)
        rescue RefError
          # The ref no longer exists, so we can't update it. Leave the old
          # checkout in place for safety; garbage collection will remove it if
          # it's no longer used.
          @logger.info("#{branch} branch missing in remote; leaving untouched")
        end
      end
    end

    def garbage_collect(code_path)
      trash_path = nil

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
          # Assume this is an object

          # Delay updating referenced until now so that we don't interfere with
          # loop detection. (Adding links as we find them would cause loops to
          # short circuit, resulting in a return of nil.)
          referenced.merge(visited)
          return target
        end
      end

      lock File::LOCK_EX, "garbage_collect #{code_path}" do
        # Remove all object locks
        FileUtils.rm Dir.glob("#{@path}/*/.*.lock")
        FileUtils.rm Dir.glob("#{@path}/*/*/.*.lock")

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
        @logger.info(
          "Deleting #{difference.size} of #{all_references.size} references")
        difference.each do |path|
          File.delete(path)
        end

        # Objects might take a while to delete, so move them into a
        # temporary directory and then delete them outside the lock.
        trash_path = new_temp_path()
        Dir.mkdir(trash_path)
        trash_sequence = 1

        all_objects = Set.new(Dir.glob("#{@path}/object/*"))
        difference = all_objects - referenced_paths
        @logger.info(
          "Trashing #{difference.size} of #{all_objects.size} objects")
        difference.each do |path|
          File.rename(path, "#{trash_path}/#{trash_sequence}")
          trash_sequence += 1
        end

        ### remove excess repos
        ### remove excess modules directories
      end
    ensure
      if trash_path and File.exist? trash_path
        @logger.info("Deleting trashed objects")
        FileUtils.remove_entry(trash_path)
        @logger.debug("Finished deleting trashed objects")
      end
    end

    def lock(mode, message=nil)
      if @lock_file
        raise "Cannot re-lock cache"
      end

      Gofer::Util::lock_file "#{@path}/lock", mode, message do |lock_file|
        @lock_file = lock_file
        yield
      end
    ensure
      @lock_file = nil
    end

  private

    def new_temp_path
      @sequence += 1
      "#{@path}/tmp/#{@process_prefix}.#{@sequence}"
    end

    def new_object_path(name=nil)
      @sequence += 1
      if name
        name = "." + name.tr("/", " ")
      end

      "#{@path}/object/#{@process_prefix}.#{@sequence}#{name}"
    end

    def fs_sanitize(ref)
      # Escape | and replace / with |. Also escape a leading .
      ref.sub(/^\./, "\\.").gsub(/[\\|]/, '\\\0').gsub(/\//, '|')
    end

    # Assumes sha exists. Use checkout() if it might not.
    def checkout_sha(repo, sha, name=nil)
      safe_sha = fs_sanitize(sha)

      repo_path = "#{@path}/sha/#{repo.name}"
      sha_path = "#{repo_path}/#{safe_sha}"
      if Dir.exist? sha_path
        return sha_path
      end

      FileUtils.mkdir_p(repo_path)

      Gofer::Util::lock sha_path, File::LOCK_EX, "checkout" do
        # Another process may have created the object before we got the lock
        if Dir.exist? sha_path
          return sha_path
        end

        object_path = new_object_path(name)
        FileUtils.mkdir_p object_path

        @logger.debug(
          "Checking out '#{sha}' from '#{repo.url}' into '#{object_path}'")
        repo.git "reset", "--hard", sha, :work_dir=>object_path
        atomic_symlink(object_path, sha_path)
      end

      sha_path
    end
  end
end
