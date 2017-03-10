require 'fileutils'
require 'logging'
require 'pathname'
require 'set'

module Armature
  class Cache
    def initialize(path)
      FileUtils.mkdir_p(path)
      @lock_file = nil
      @path = File.realpath(path)
      @repos = {}
      @process_prefix = "#{Time.now.to_i}.#{Process.pid}"
      @sequence = 0
      @logger = Logging.logger[self]

      %w{repo ref/mutable ref/immutable ref/identity object tmp}.each do |subdir|
        FileUtils.mkdir_p("#{@path}/#{subdir}")
      end
    end

    def flush_memory!
      @logger.debug("Flushing in-memory caches for all repos")
      @repos.each do |name, repo|
        repo.freshen!
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
        Armature::Util::lock repo_path, File::LOCK_EX, "clone" do
          if Dir.exist? repo_path
            @logger.info("Another process cloned '#{url}' while we were blocked")
          else
            # Mirror copies *all* refs, not just branches. Ignore output.
            Armature::Run.command(
              "git", "clone", "--quiet", "--mirror", url, repo_path)
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
    def checkout(repo, ref, refresh=false, options={})
      if refresh
        # Don't check the cache; refresh it from source.
        repo.freshen()
        ref = repo.canonical_ref(ref)
      else
        # This will raise a RefError if the ref doesn't exist
        begin
          ref = repo.canonical_ref(ref)
        rescue RefError
          repo.freshen()
          ref = repo.canonical_ref(ref)
        end
      end

      type = repo.ref_type(ref)
      safe_ref = fs_sanitize(ref)
      repo_path = "#{@path}/ref/#{type}/#{repo.name}"
      ref_path = "#{repo_path}/#{safe_ref}"

      if ! refresh
        # Check cache first
        if Dir.exist? ref_path
          return ref_path
        end
      end

      FileUtils.mkdir_p(repo_path)

      identity_path = checkout_identity(repo, repo.ref_identity(ref))
      if identity_path != ref_path
        atomic_symlink(identity_path, ref_path)
      end

      ref_path
    end

    # Creates a symlink atomically
    #
    # That is, if a symlink or file exists at new_path, then this will replace
    # it with the newly created symlink atomically.
    #
    # Both target_path and new_path must be absolute.
    def atomic_symlink(target_path, new_path)
      new_path.chomp!("/")

      @logger.debug("#{new_path} -> #{target_path}")

      begin
        if File.readlink(new_path) == target_path
          return
        end
      rescue Errno::ENOENT
      end

      temp_path = new_temp_path()
      File.symlink(target_path, temp_path)
      File.rename(temp_path, new_path)
    rescue
      @logger.error("Error in atomic_symlink('#{target_path}', '#{new_path}')")
      raise
    end

    def update_branches()
      Dir.glob("#{@path}/ref/mutable/*/*") do |path|
        ref = fs_unsanitize(File.basename(path))
        repo = get_repo_by_name(File.basename(File.dirname(path)))
        @logger.info("Updating #{ref} ref from #{repo.url}")

        begin
          checkout(repo, ref, :refresh=>true)
        rescue RefError
          # The ref no longer exists, so we can't update it. Leave the old
          # checkout in place for safety; garbage collection will remove it if
          # it's no longer used.
          @logger.info("#{ref} ref missing in remote; leaving untouched")
        end
      end
    end

    def garbage_collect(environments_path)
      lock File::LOCK_EX, "garbage_collect #{environments_path}" do
        # Remove all object locks
        FileUtils.rm Dir.glob("#{@path}/*/.*.lock")
        FileUtils.rm Dir.glob("#{@path}/*/*/.*.lock")

        referenced_paths = find_all_references(environments_path)

        garbage_collect_refs(referenced_paths)
        garbage_collect_objects(referenced_paths)
        garbage_collect_repos()

        ### remove excess modules directories
      end
    ensure
      empty_trash()
    end

    def lock(mode, message=nil)
      if @lock_file
        raise "Cannot re-lock cache"
      end

      Armature::Util::lock_file "#{@path}/lock", mode, message do |lock_file|
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
      ref.sub(/\A\./, "\\.").gsub(/[\\|]/, '\\\0').gsub(/\//, '|')
    end

    def fs_unsanitize(name)
      name.gsub(/\|/, '/').gsub(/\\([\\|])/, '\0').sub(/^\\\./, '.')
    end

    # Assumes identity exists. Use checkout() if it might not.
    def checkout_identity(repo, identity)
      safe_identity = fs_sanitize(identity)

      repo_path = "#{@path}/identity/#{repo.name}"
      identity_path = "#{repo_path}/#{safe_identity}"
      if Dir.exist? identity_path
        return identity_path
      end

      FileUtils.mkdir_p(repo_path)

      Armature::Util::lock identity_path, File::LOCK_EX, "checkout" do
        # Another process may have created the object before we got the lock
        if Dir.exist? identity_path
          return identity_path
        end

        object_path = new_object_path(identity)
        FileUtils.mkdir_p object_path

        @logger.debug(
          "Checking out '#{identity}' from '#{repo.url}' into '#{object_path}'")
        repo.git "reset", "--hard", identity, :work_dir=>object_path
        atomic_symlink(object_path, identity_path)
      end

      identity_path
    end

    # Put a directory into a trash directory for off-line deletion
    #
    # Directories take a while to delete, so move them into a temporary
    # directory and then delete them outside the lock.
    def trash(path)
      if not @trash_path or not File.directory? @trash_path
        @trash_path = new_temp_path()
        Dir.mkdir(@trash_path)
        @trash_sequence = 1
      end

      File.rename(path, "#{@trash_path}/#{@trash_sequence}")
      @trash_sequence += 1
    end

    def empty_trash
      if @trash_path and File.exist? @trash_path
        @logger.info("Deleting trashed objects")
        FileUtils.remove_entry(@trash_path)
        @logger.debug("Finished deleting trashed objects")
      end

      @trash_path = nil
      @trash_sequence = nil
    end

    # Part of find_all_references
    def follow_reference(path, referenced, visited=[])
      if not File.symlink? path
        raise "Expected a symlink: #{path}"
      end

      target = Pathname.new(File.readlink(path)).cleanpath.to_s
      if referenced.include? target
        # Short cut. We've already seen this path.
        @logger.debug("follow_reference: shortcutting #{path} -> #{target}")
        return nil
      end

      @logger.debug("follow_reference: #{path} -> #{target}")

      visited << target

      if File.symlink? target
        if visited.size() >= 6
          raise "Symlink path more than 6 links deep: #{visited}"
        end

        target = follow_reference(target, referenced, visited)
      elsif File.directory? target
        # Assume this is an object
        @logger.debug("follow_reference: object: #{target}")
      elsif not File.exist? target
        @logger.warn("follow_reference: does not exist: #{target}")
      else
        @logger.error("follow_reference: not an object or symlink: #{target}")
      end

      # Delay updating referenced until now so that we don't interfere with
      # loop detection. (Adding links as we find them would cause loops to
      # short circuit, resulting in a return of nil.)
      referenced.merge(visited)
      return target
    end

    def find_all_references(environments_path)
      referenced_paths = Set.new
      environments = Dir.glob("#{environments_path}/*")

      @logger.debug(
        "Looking for references in #{environments.count} environments")

      environments.each do |env_path|
        object_path = follow_reference(env_path, referenced_paths)
        if object_path
          # We could get a nil if two branches evaluate to the same sha.
          referenced_paths << object_path

          Dir.glob("#{object_path}/modules/*") do |module_path|
            follow_reference(module_path, referenced_paths)
          end
        end
      end

      referenced_paths
    end

    def garbage_collect_refs(referenced_paths)
      # Must be run from garbage_collect, since that handles the lock as well
      # as emptying the trash
      all_references = Set.new(Dir.glob("#{@path}/ref/*/*/*"))
      difference = all_references - referenced_paths
      @logger.info(
        "Deleting #{difference.size} of #{all_references.size} references")
      difference.each do |path|
        @logger.debug("Deleting #{path} (unused)")
        File.delete(path)
      end
    end

    def garbage_collect_objects(referenced_paths)
      # Must be run from garbage_collect, since that handles the lock as well
      # as emptying the trash
      all_objects = Set.new(Dir.glob("#{@path}/object/*"))
      difference = all_objects - referenced_paths
      @logger.info(
        "Trashing #{difference.size} of #{all_objects.size} objects")
      difference.each do |path|
        @logger.debug("Trashing #{path} (unused)")
        trash(path)
      end
    end

    def garbage_collect_repos
      # Must be run from garbage_collect, since that handles the lock as well
      # as emptying the trash
      all_repos = Dir.glob("#{@path}/repo/*")
      all_repos = Set.new(all_repos.map { |path| File.basename(path) })
      used_repos = Set.new()

      referenced_repos = Dir.glob("#{@path}/ref/*/*")
      referenced_repos.each do |path|
        # No refs within the repo in use (for this ref type)
        if Dir.glob("#{path}/*").empty?
          @logger.debug("Trashing #{path} (empty)")
          trash(path)
        else
          used_repos << File.basename(path)
        end
      end

      difference = all_repos - used_repos
      @logger.info(
        "Trashing #{difference.size} of #{all_repos.size} repos")
      difference.each do |repo|
        @logger.debug("Trashing #{@path}/repo/#{repo} (unused)")
        trash("#{@path}/repo/#{repo}")
      end
    end
  end
end
