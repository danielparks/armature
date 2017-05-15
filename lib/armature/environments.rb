module Armature
  class Environments
    class InvalidNameError < Armature::Error
    end

    # https://docs.puppet.com/puppet/latest/reference/lang_reserved.html#environments
    def self.assert_valid_environment_name(name)
      if name !~ /\A[a-z0-9_]+\Z/
        raise InvalidNameError, "Invalid environment name '#{name}'"
      end
    end

    def self.assert_valid_module_name(name)
      if name !~ /\A[a-z][a-z0-9_]*\Z/
        raise InvalidNameError, "Invalid module name '#{name}'"
      end
    end

    attr_reader :path

    # path is the path to the directory containing all the environments
    def initialize(path, cache)
      @cache = cache
      @logger = Logging.logger[self]

      if not File.directory? path
        abort "Puppet environments path does not exist: '#{path}'"
      end

      @path = File.realpath(path)
    end

    def names()
      Dir["#{@path}/*"].map { |path| File.basename(path) }
    end

    def remove(name)
      File.delete("#{@path}/#{name}")
      @logger.debug "Environment '#{name}' deleted"
    rescue Errno::ENOENT
      @logger.debug "Environment '#{name}' does not exist"
    end

    def checkout_ref(repo, ref, name=ref)
      # This will add and update a modules dir in any repo, even if the repo is
      # used in a Puppetfile. (Perhaps the cache is used for multiple repos?)
      self.class.assert_valid_environment_name(name)

      @cache.lock File::LOCK_SH do
        @logger.info "Deploying ref '#{ref}' from '#{repo.url}' as" \
          " environment '#{name}'"

        begin
          ref_path = @cache.checkout(repo, ref, true)
        rescue Armature::GitRepo::RefError
          @logger.info "Ref '#{ref}' does not exist; ensuring environment" \
            " '#{name}' is gone"
          remove(name)
          return
        end

        puppetfile_path = "#{ref_path}/Puppetfile"
        if File.exist?(puppetfile_path)
          @logger.debug "Found Puppetfile in environment '#{name}'"
          module_refs = Armature::Puppetfile.new().include(puppetfile_path)
          @logger.debug "Loaded Puppetfile in environment '#{name}' with" \
            " #{module_refs.length} modules"
        else
          @logger.debug "No Puppetfile in environment '#{name}'"
          module_refs = {}
        end

        update_modules(ref_path, module_refs)

        @cache.atomic_symlink(ref_path, "#{@path}/#{name}")
        @logger.debug "Done deploying ref '#{ref}' from '#{repo.url}' as" \
          " environment '#{name}'"
      end
    end

  private

    # Apply the results of the Puppetfile to a ref (e.g. an environment)
    def update_modules(target_path, module_refs)
      modules_path = "#{target_path}/modules"
      if ! Dir.exist? modules_path
        Dir.mkdir(modules_path)
      end

      module_refs.each do |name, info|
        self.class.assert_valid_module_name(name)

        ref_path = @cache.checkout(@cache.get_repo(info[:git]), info[:ref])

        @cache.atomic_symlink(ref_path, "#{modules_path}/#{name}")
      end

      Dir.foreach(modules_path) do |name|
        if ! module_refs.has_key? name and name != "." and name != ".."
          # All paths should be symlinks.
          File.delete("#{modules_path}/#{name}")
        end
      end
    end
  end
end
