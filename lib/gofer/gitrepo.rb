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
      @ref_cache = {}
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
      data = git("for-each-ref",
          "--format", "%(objectname) %(refname:strip=2)",
          "refs/heads")
      lines = data.split(/[\r\n]/).reject { |line| line == "" }

      lines.map do |line|
        hash, name = line.split(' ', 2)
        @ref_cache[name] = [:branch, hash]
        name
      end
    end

    # Get the type of a ref (:branch, :tag, or :sha) and its sha as [type, sha]
    def ref_info(ref)
      if @ref_cache[ref]
        @ref_cache[ref]
      elsif sha = rev_parse("refs/heads/#{ref}")
        @ref_cache[ref] = [:branch, sha]
      elsif sha = rev_parse("refs/tags/#{ref}")
        @ref_cache[ref] = [:tag, sha]
      elsif sha = rev_parse(ref)
        if sha == ref
          @ref_cache[ref] = [:sha, sha]
        else
          raise "Unknown ref type for '#{ref}'"
        end
      else
        raise RefError.new("no such ref '#{ref}' in repo '#{url}'")
      end
    end

  private

    # Get the sha for a ref, or nil if it doesn't exist
    def rev_parse(ref)
      if @ref_cache[ref]
        @ref_cache[ref][1]
      else
        git("rev-parse", "--verify", "#{ref}^{commit}").chomp
      end
    rescue Gofer::Run::CommandFailureError
      nil
    end
  end
end
