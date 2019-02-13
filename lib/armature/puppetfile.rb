module Armature
  class Puppetfile
    attr_reader :results

    def initialize(cache)
      @cache = cache
      @results = {}
      @logger = Logging.logger[self]
      @forge_url = "https://forge.puppet.com"
      @moduledir = 'modules'
    end

    ### FIXME this will have access to @cache and @results
    def include(path)
      instance_eval(IO.read(path), path)
      @results
    end

    # Apply the results of the Puppetfile to a ref (e.g. an environment)
    #
    ### FIXME This could update modules in an existing check out.
    def update_modules(target_path, module_refs)
      modules_path = "#{target_path}/#{@moduledir}"
      if ! Dir.exist? modules_path
        Dir.mkdir(modules_path)
      end

      module_refs.each do |name, info|
        Armature::Environments.assert_valid_module_name(name)

        ref_path = info[:ref].check_out()
        @cache.atomic_symlink(ref_path, "#{modules_path}/#{name}")
      end

      Dir.foreach(modules_path) do |name|
        if ! module_refs.has_key? name and name != "." and name != ".."
          # All paths should be symlinks.
          File.delete("#{modules_path}/#{name}")
        end
      end
    end

    def forge(url)
      @forge_url = url.chomp("/")
    end

    def moduledir(path)
      @moduledir = path
    end

    def mod(full_name, options={})
      name = full_name.split("-", 2).last()
      Armature::Environments.assert_valid_module_name(name)

      if @results[name]
        raise "Module #{name} declared twice"
      end

      is_forge = options.is_a?(Symbol) \
        || options.is_a?(String) \
        || options == {} \
        || options == nil

      if is_forge
        _mod_forge(full_name, name, options)
      elsif options[:git]
        _mod_git(name, options)
      else
        raise "Invalid mod call: #{full_name} #{options}"
      end
    end

    def _mod_forge(full_name, name, version=:latest)
      if version == nil || version == {}
        version = "latest"
      else
        version = version.to_s
      end

      repo = Repo::Forge.from_url(@cache, @forge_url, full_name)
      ref = repo.general_ref(version)
      @logger.debug("mod #{name}: #{ref}")
      @results[name] = { :name => name, :ref => ref }
    end

    def _mod_git(name, options={})
      options = Armature::Util.process_options(options, {
        :commit => nil,
        :tag => nil,
        :branch => nil,
        :ref => nil,
      }, {
        :git => nil,
      })

      repo = Repo::Git.from_url(@cache, options[:git])
      ref = nil

      if options[:commit]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = repo.identity_ref(options[:commit])
      end

      if options[:tag]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = repo.tag_ref(options[:tag])
      end

      if options[:branch]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = repo.branch_ref(options[:branch])
      end

      if options[:ref]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = repo.general_ref(options[:ref])
      end

      if ! ref
        ref = repo.branch_ref("master")
      end

      @logger.debug("mod #{name}: #{ref}")
      @results[name] = { :name => name, :ref => ref }
    end
  end
end
