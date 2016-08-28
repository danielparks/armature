module Gofer
  class RefError < StandardError
  end

  class GitRepo
    attr_reader :name

    def initialize(git_dir, name)
      @git_dir = git_dir
      @name = name
      @fetched = false
      @logger = Logging.logger[self]
    end

    def url
      @url ||= git("config", "--get", "remote.origin.url").chomp()
    end

    def freshen
      if ! @fetched
        @logger.info("Fetching from #{url}")
        Gofer::Util::lock @git_dir, File::LOCK_EX, "fetch" do
          # Use --force to handle history changes
          git "remote", "update", "--prune"
        end
        @fetched = true
        true
      else
        false
      end
    end

    def git(*arguments)
      # This accepts a hash of options as the last argument
      options = if arguments.last.is_a? Hash then arguments.pop else {} end
      options = Gofer::Util.process_options(options, { :work_dir => nil }, {})

      if options[:work_dir]
        work_dir_arguments = [ "--work-tree=" + options[:work_dir] ]
      else
        work_dir_arguments = []
      end

      command = [ "git", "--git-dir=" + @git_dir ] \
        + work_dir_arguments \
        + arguments

      Gofer::Run.command(*command)
    end

    def get_branches()
      freshen()
      git("for-each-ref", "--format", "%(refname:strip=2)", "refs/heads")
        .split(/[\r\n]/)
        .reject { |line| line == "" }
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
        raise RefError.new("no such ref '#{ref}' in repo '#{url}'")
      end
    end

    # Get the sha for a ref, or nil if it doesn't exist
    def ref_sha(ref)
      git("rev-parse", "--verify", "#{ref}^{commit}").chomp
    rescue Gofer::Run::CommandFailureError
      nil
    end

    # Get the sha for a ref, fetching once if it doesn't exist
    def find_ref_sha(ref)
      sha = ref_sha(ref)
      if sha.nil? and freshen()
        # git fetch was actually called
        sha = ref_sha(ref)
      end

      if sha.nil?
        raise RefError.new("no such ref '#{ref}' in repo '#{url}'")
      end

      sha
    end
  end
end
