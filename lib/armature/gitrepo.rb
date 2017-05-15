module Armature
  class GitRepo
    class RefError < Armature::Error
    end

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
        freshen!
        true
      else
        false
      end
    end

    def freshen!
      @logger.info("Fetching from #{url}")
      Armature::Util::lock @git_dir, File::LOCK_EX, "fetch" do
        git "remote", "update", "--prune"
      end
      @ref_cache = {}
      @fetched = true
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
          "--format", "%(objectname) %(refname)",
          "refs/heads")
      lines = data.split(/[\r\n]/).reject { |line| line == "" }

      lines.map do |line|
        sha, ref = line.split(' ', 2)
        name = ref.sub("refs/heads/", "")
        @ref_cache[ref] = [:mutable, sha, ref, "branch", name]
        name
      end
    end

    def ref_type(ref)
      ref_info(ref)[0]
    end

    def ref_identity(ref)
      ref_info(ref)[1]
    end

    def canonical_ref(ref)
      ref_info(ref)[2]
    end

    def ref_human_name(ref)
      info = ref_info(ref)

      "#{info[3]} '#{info[4]}'"
    end

  private

    # Get information about ref, checking the cache first
    def ref_info(ref)
      if ! @ref_cache[ref]
        freshen_ref_cache(ref)
      end

      @ref_cache[ref]
    end

    # Get information about a ref and put it in the cache
    def freshen_ref_cache(ref)
      if ref.start_with? "refs/heads/"
        @ref_cache[ref] = [:mutable, rev_parse!(ref), ref, "branch", ref.sub("refs/heads/", "")]
      elsif ref.start_with? "refs/tags/"
        @ref_cache[ref] = [:immutable, rev_parse!(ref), ref, "tag", ref.sub("refs/tags/", "")]
      elsif ref.start_with? "refs/"
        @ref_cache[ref] = [:mutable, rev_parse!(ref), ref, "ref", ref]
      elsif sha = rev_parse("refs/heads/#{ref}")
        @ref_cache["refs/heads/#{ref}"] = [:mutable, sha, "refs/heads/#{ref}", "branch", ref]
        @ref_cache[ref] = @ref_cache["refs/heads/#{ref}"]
      elsif sha = rev_parse("refs/tags/#{ref}")
        @ref_cache["refs/tags/#{ref}"] = [:immutable, sha, "refs/tags/#{ref}", "tag", ref]
        @ref_cache[ref] = @ref_cache["refs/tags/#{ref}"]
      elsif sha = rev_parse(ref)
        if sha == ref
          @ref_cache[ref] = [:identity, sha, ref, "revision", ref]
        else
          @ref_cache[ref] = [:mutable, sha, ref, "ref", ref]
        end
      else
        raise RefError, "no such ref '#{ref}' in repo '#{url}'"
      end
    end

    # Get the sha for a ref, or nil if it doesn't exist
    def rev_parse(ref)
      rev_parse!(ref)
    rescue RefError
      nil
    end

    # Get the sha for a ref, or raise if it doesn't exist
    def rev_parse!(ref)
      git("rev-parse", "--verify", "#{ref}^{commit}").chomp
    rescue Armature::Run::CommandFailureError
      raise RefError, "no such ref '#{ref}' in repo '#{url}'"
    end
  end
end
