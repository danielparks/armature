module Gofer
  class GitRepo
    attr_reader :name

    def initialize(name, git_dir)
      @name = name
      @git_dir = git_dir
      @fetched = false
    end

    def freshen
      if @fetched
        self.git "fetch"
        @fetched = true
        true
      else
        false
      end
    end

    def git(*arguments)
      # This accepts a hash of options as the last argument
      options = if arguments.last.is_a? Hash then arguments.pop else {} end
      options = Gofer::Util.process_options(options, {}, {
        :work_dir => ".",
      })

      command = [ "git",
        "--work-tree=" + options[:work_dir],
        "--git-dir=#{@git_dir}/",
      ] + arguments

      ### handle errors? missing git?
      Gofer::Run.command(*command)
    end

    def ref_type(ref)
      output = self.git "show-ref", ref
      output.split("\n").each do |line|
        symbol = line.split(" ", 2)[1]
        if symbol.starts_with?("refs/remotes/origin/")
          return :branch
        elsif symbol.starts_with?("refs/tags/")
          return :tag
        elsif symbol.starts_with?("refs/heads/")
          # Local branch
          return :branch
        else
          ### unknown. log? error?
          raise "Unknown ref type: #{ref}"
        end
      end

      raise "Could not find ref: #{ref}"
    rescue CommandFailureError
      ### Not 100% certain this is correct
      self.git "show-ref", "--verify", ref
      return :sha
    end

    # Get a ref's sha, failing if it doesn't exist
    def ref_sha!(ref)
      self.git "rev-parse", ref
    rescue CommandFailureError
      raise IndexError.new("no such ref '#{ref}'")
    end

    # Get a ref's sha, fetching once if it doesn't exist
    def ref_sha(ref)
      sha = self.ref_sha!(ref)
    rescue IndexError
      if self.freshen
        # git fetch was actually called
        sha = self.ref_sha!(ref)
      else
        # fetch had already been run recently
        raise
      end
    end
  end
end
