module Gofer
  class Environments
    attr_reader :path

    # path is the path to the directory containing all the environments
    def initialize(path, cache)
      @cache = cache
      @path = path
      @logger = Logging.logger[self]
    end

    def checkout_ref(repo, ref)
      # This will add and update a modules dir in any repo, even if the repo is
      # used in a Puppetfile. (Perhaps the cache is used for multiple repos?)

      @cache.lock File::LOCK_SH do
        logger = Logging.logger["#{self.class.name} #{ref}"]
        logger.info "Deploying from '#{repo.url}'"

        environment_path = "#{@path}/#{ref}"

        begin
          ref_path = @cache.checkout(repo, ref, :name=>ref, :refresh=>true)
        rescue RefError
          if File.exist? environment_path
            logger.info "Does not exist. Deleting environment."
            File.delete(environment_path)
          else
            logger.info "Does not exist. No environment to delete."
          end
          return
        end

        puppetfile_path = "#{ref_path}/Puppetfile"
        if File.exist?(puppetfile_path)
          logger.debug "Found Puppetfile"
          puppetfile = Gofer::Puppetfile.new()
          puppetfile.include(puppetfile_path)
          module_refs = puppetfile.results
          logger.debug "Loaded Puppetfile with #{module_refs.length} modules"
        else
          logger.debug "No Puppetfile"
          module_refs = {}
        end

        update_modules(ref_path, module_refs)

        @cache.atomic_symlink(ref_path, environment_path)
        logger.debug "Done deploying from '#{repo.url}'"
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
        if name !~ /^[a-z][a-z0-9_]*$/
          raise "Invalid module name: '#{name}'"
        end

        repo =  @cache.get_repo(info[:git])
        ref_path = @cache.checkout(repo, info[:ref], :name=>"#{name}.#{info[:ref]}")

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
