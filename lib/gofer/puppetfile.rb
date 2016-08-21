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
      # https://docs.puppet.com/puppet/latest/reference/lang_reserved.html#classes-and-defined-resource-types
      if name !~ /^[a-z][a-z0-9_]*$/
        raise "Invalid module name: '#{name}'"
      end

      if @results[name]
        raise "Module #{name} declared twice"
      end

      @results[name] = Gofer::Util.process_options(options, {}, {
        :git => nil,
        :ref => "master",
      })
    end

    def forge(*arguments)
      ### error?
    end
  end
end
