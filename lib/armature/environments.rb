module Armature
  class Environments
    class InvalidNameError < Armature::Error
    end

    # The documentation claims that uppercase letters are invalid, but in
    # practice they seem to be fine.
    #
    # https://docs.puppet.com/puppet/latest/reference/lang_reserved.html#environments
    def self.valid_environment_name?(name)
      name =~ /\A[A-Za-z0-9_]+\Z/
    end

    def self.assert_valid_environment_name(name)
      if ! valid_environment_name?(name)
        raise InvalidNameError, "Invalid environment name '#{name}'"
      end
    end

    # Same rules as for a class
    def self.assert_valid_module_name(name)
      if name !~ /\A[a-z][a-z0-9_]*\Z/
        raise InvalidNameError, "Invalid module name '#{name}'"
      end
    end

    attr_reader :path
    attr_accessor :fix_environment_names

    # path is the path to the directory containing all the environments
    def initialize(path, cache)
      @cache = cache
      @logger = Logging.logger[self]
      @fix_environment_names = false

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

    def normalize_environment_name(name)
      if @fix_environment_names && ! self.class.valid_environment_name?(name)
        old = name
        name = old.gsub(/[^A-Za-z0-9_]/, "_")
        @logger.warn("Changing invalid environment name \"#{old}\" to \"#{name}\"")
      end

      self.class.assert_valid_environment_name(name)
      name
    end

    # Create an environment from a ref
    #
    # This will add and update a modules dir in any repo, even if the repo is
    # used in a Puppetfile. (Perhaps the cache is used for multiple repos?)
    def check_out_ref(repo, ref_str, name=ref_str)
      name = normalize_environment_name(name)

      @cache.lock File::LOCK_SH do
        @logger.info "Deploying ref '#{ref_str}' from '#{repo}' as" \
          " environment '#{name}'"

        begin
          ref_path = repo.general_ref(ref_str).check_out()
        rescue Armature::RefError
          @logger.info "Ref '#{ref_str}' does not exist; ensuring environment" \
            " '#{name}' is gone"
          remove(name)
          return
        end

        puppetfile = Armature::Puppetfile.new(@cache)
        puppetfile.load_control_directory(ref_path)
        puppetfile.update_modules(ref_path)

        # Make the change live
        @cache.atomic_symlink(ref_path, "#{@path}/#{name}")
        @logger.debug "Done deploying ref '#{ref_str}' from '#{repo}' as" \
          " environment '#{name}'"
      end
    end
  end
end
