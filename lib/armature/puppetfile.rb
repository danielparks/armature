module Armature
  class Puppetfile
    attr_reader :results

    def initialize()
      @results = {}
    end

    def include(path)
      instance_eval(IO.read(path), path)
    end

    def mod(name, options={})
      if name =~ /\A\./
        raise "Module name may not start with period: '#{name}'"
      elsif name =~ /\//
        raise "Module name may not contain /: '#{name}'"
      end

      if @results[name]
        raise "Module #{name} declared twice"
      end

      @results[name] = Armature::Util.process_options(options, {}, {
        :git => nil,
        :ref => "master",
      })
    end

    def forge(*arguments)
      ### error?
    end
  end
end
