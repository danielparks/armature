module Gofer
  class GitRepo
    attr_reader :name
    attr_reader :url

    def initialize(url, name, git_dir)
      @url = url
      @name = name
      @git_dir = git_dir
      @fetched = false
    end

    def freshen
      if ! @fetched
        git "fetch"
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
        "--git-dir=" + @git_dir,
      ] + arguments

      ### handle errors? missing git?
      puts Gofer::Run.command_to_string(*command)
      Gofer::Run.command(*command)
    end

    # Get the type of a ref (:branch, :tag, or :sha)
    def ref_type(ref)
      if ref_sha("refs/heads/#{ref}")
        :branch
      elsif ref_sha("refs/tags/#{ref}")
        :tag
      elsif ref_sha(ref)
        if sha == ref
          :sha
        else
          raise "Unknown ref type for '#{ref}'"
        end
      else
        raise IndexError.new("no such ref '#{ref}'")
      end
    end

    # Get the sha for a ref, or nil if it doesn't exist
    def ref_sha(ref)
      git("rev-parse", ref).chomp
    rescue Gofer::Run::CommandFailureError
      nil
    rescue => e
      puts e.class
      raise
    end

    # Get the sha for a ref, fetching once if it doesn't exist
    def find_ref_sha(ref)
      sha = ref_sha(ref)
      if sha.nil? and freshen()
        # git fetch was actually called
        sha = ref_sha(ref)
      end

      if sha.nil?
        raise IndexError.new("no such ref '#{ref}'")
      end

      sha
    end
  end
end
