module Armature
  class Puppetfile
    attr_reader :results

    def initialize()
      @results = {}
    end

    def include(path)
      instance_eval(IO.read(path), path)
      @results
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

      options = Armature::Util.process_options(options, {
        :commit => nil,
        :tag => nil,
        :branch => nil,
        :ref => nil,
      }, {
        :git => nil,
      })

      ref = nil

      if options[:commit]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = options[:commit]
      end

      if options[:tag]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = "refs/tags/#{options[:tag]}"
      end

      if options[:branch]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = "refs/heads/#{options[:branch]}"
      end

      if options[:ref]
        if ref
          raise "Module #{name} has more than one of :commit, :tag, :branch, or :ref"
        end
        ref = options[:ref]
      end

      if ! ref
        ref = "refs/heads/master"
      end

      @results[name] = { :name => name, :ref => ref, :git => options[:git] }
    end

    def forge(*arguments)
      ### error?
    end
  end
end
