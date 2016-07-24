module Gofer
  class Puppetfile
    attr_reader :results

    def initialize(cache)
      @cache = cache
      @results = {}
    end

    def include(path)
      instance_eval(IO.read(path), path)
    end

    def mod(name, options={})
      if @results[name]
        raise "Module #{name} declared twice"
      end

      options = Gofer::Util.process_options(options, {}, {
        :git => nil,
        :ref => "master",
      })

      repo =  @cache.get_repo(options[:git])
      ref_path = @cache.get_ref_path(repo, options[:ref])

      @results[name] = ref_path
    end

    def forge
      ### error?
    end
  end
end
