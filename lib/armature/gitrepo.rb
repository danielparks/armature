module Armature
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
        Armature::Util::lock @git_dir, File::LOCK_EX, "fetch" do
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
      options = Armature::Util.process_options(options, { :work_dir => nil }, {})

      if options[:work_dir]
        work_dir_arguments = [ "--work-tree=" + options[:work_dir] ]
      else
        work_dir_arguments = []
      end

      command = [ "git", "--git-dir=" + @git_dir ] \
        + work_dir_arguments \
        + arguments

      Armature::Run.command(*command)
    end

    def get_branches()
      freshen()
      data = git("for-each-ref",
          "--format", "%(objectname) %(refname:strip=2)",
          "refs/heads")
      lines = data.split(/[\r\n]/).reject { |line| line == "" }

      lines.map do |line|
        sha, branch = line.split(' ', 2)
        ref = "refs/heads/#{branch}"
        @ref_cache[ref] = [:mutable, sha, ref]
        branch
      end
    end

    # Get the type of a ref (:branch, :tag, or :sha) and its sha as [type, sha]
    def ref_info(ref)
      if result = check_cache(ref)
        result
      elsif sha = rev_parse("refs/heads/#{ref}")
        @ref_cache["refs/heads/#{ref}"] = [:mutable, sha, "refs/heads/#{ref}"]
      elsif sha = rev_parse("refs/tags/#{ref}")
        @ref_cache["refs/tags/#{ref}"] = [:immutable, sha, "refs/tags/#{ref}"]
      elsif sha = rev_parse(ref)
        if sha == ref
          @ref_cache[ref] = [:immutable, sha, ref]
        else
          @ref_cache[ref] = [:mutable, sha, ref]
        end
      else
        raise RefError.new("no such ref '#{ref}' in repo '#{url}'")
      end
    end

  private
    def check_cache(ref)
      @ref_cache[ref] \
      || @ref_cache["refs/heads/#{ref}"] \
      || @ref_cache["refs/tags/#{ref}"]
    end

    # Get the sha for a ref, or nil if it doesn't exist
    def rev_parse(ref)
      git("rev-parse", "--verify", "#{ref}^{commit}").chomp
    rescue Armature::Run::CommandFailureError
      nil
    end
  end
end
