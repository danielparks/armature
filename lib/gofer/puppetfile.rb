module Gofer
  class Puppetfile
    attr_reader :results

    def initialize()
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

      @results[name] = options
    end

    def forge(*arguments)
      ### error?
    end
  end
end
