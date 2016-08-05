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

      options = Gofer::Util.process_options(options, {}, {
        :git => nil,
        :ref => "master",
      })

      if options[:ref].start_with? "."
        raise "ref may not start with '.': '#{options[:ref]}'"
      end

      if options[:ref].include? "/"
        raise "ref may not contain '/': '#{options[:ref]}'"
      end

      @results[name] = options
    end

    def forge(*arguments)
      ### error?
    end
  end
end
