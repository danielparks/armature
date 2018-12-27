class Armature::Repo::Git < Armature::Repo
  # Gets a repo object for a given URL. Mirrors the repo in the local cache
  # if it doesn't already exist.
  def self.from_url(cache, url)
    repo = cache.get_repo("git", url)
    if repo
      return repo
    end

    fresh = false
    repo_dir = cache.open_repo("git", url) do |temp_path|
      Logging.logger[self].debug("Cloning '#{url}' for the first time")

      # Mirror copies *all* refs, not just branches. Ignore output.
      Armature::Run.clean_git("clone", "--quiet", "--mirror", url, temp_path)
      fresh = true

      Logging.logger[self].debug("Done cloning '#{url}'")
    end

    return self.new(cache, repo_dir, fresh)
  end

  def initialize(cache, repo_dir, is_fresh=false)
    super(cache, repo_dir)
    @fresh = is_fresh
  end

  def url
    @url ||= git("config", "--get", "remote.origin.url").chomp()
  end

  # Check out a ref from a repo and return the path
  def check_out(ref)
    @logger.debug("Checking out #{ref} from #{self}")
    @cache.open_ref(ref) do |object_path|
      git "reset", "--hard", ref.identity, :work_dir=>object_path
    end
  end

  def freshen!
    flush_memory!

    @logger.info("Fetching from #{url}")
    Armature::Util::lock(@repo_dir, File::LOCK_EX, "fetch") do
      ### FIXME Only flush memory if this makes changes
      git "remote", "update", "--prune"
    end
    @fresh = true
  end

  def flush_memory!
    @fresh = false
    @ref_cache = {}
    @rev_cache = {}
  end

  # Get ref object
  def general_ref(ref_str)
    return @ref_cache[ref_str] if @ref_cache[ref_str]

    if ref_str.start_with? "refs/heads/"
      return branch_ref(ref_str.sub("refs/heads/", ""))
    end

    if ref_str.start_with? "refs/tags/"
      return tag_ref(ref_str.sub("refs/tags/", ""))
    end

    retry_fresh do
      if ref_str.start_with? "refs/"
        freshen()
        return make_ref(Armature::Ref::Mutable, ref_str, rev_parse!(ref_str),
          "ref", ref_str)
      end

      if sha = rev_parse("refs/heads/#{ref_str}")
        return branch_ref(ref_str)
      end

      if sha = rev_parse("refs/tags/#{ref_str}")
        return tag_ref(ref_str)
      end

      # This could trigger a retry
      sha = rev_parse!(ref_str)
      if sha_match? sha, ref_str
        return identity_ref(sha)
      end

      # It exists, but it's outside of refs/. Treat it as mutable.
      make_ref(Armature::Ref::Mutable, ref_str, sha, "ref", ref_str)
    end
  end

  # Get ref object for some sort of mutable ref we found in the FS cache
  def mutable_fs_ref(ref_str)
    freshen()

    return @ref_cache[ref_str] if @ref_cache[ref_str]

    if ref_str.start_with? "refs/heads/"
      return branch_ref(ref_str.sub("refs/heads/", ""))
    end

    if ref_str.start_with? "refs/tags/"
      return tag_ref(ref_str.sub("refs/tags/", ""))
    end

    make_ref(Armature::Ref::Mutable, ref_str, rev_parse!(ref_str), "ref", ref_str)
  end

  # The identity of an object itself, i.e. a SHA
  def identity_ref(sha)
    return @ref_cache[sha] if @ref_cache[sha]

    real_sha = nil # needs to be bound to this scope
    retry_fresh do
      # real_sha will always be a full SHA, but sha might be partial
      real_sha = rev_parse!(sha)
      if ! sha_match? real_sha, sha
        raise Armature::RefError, "'#{sha}' is not a Git SHA"
      end
    end

    make_ref(Armature::Ref::Identity, real_sha, real_sha, "revision", real_sha)

    # If sha is partial, register it in the cache too.
    @ref_cache[sha] = @ref_cache[real_sha]
  end

  def branch_ref(name)
    ref_str = "refs/heads/#{name}"
    freshen()

    return @ref_cache[ref_str] if @ref_cache[ref_str]

    sha = rev_parse!(ref_str)
    _branch_ref(ref_str, name, sha)
  end

  def _branch_ref(ref_str, name, sha)
    make_ref(Armature::Ref::Mutable, ref_str, sha, "branch", name)
    @ref_cache[name] = @ref_cache[ref_str]
  end

  def tag_ref(name)
    ref_str = "refs/tags/#{name}"
    return @ref_cache[ref_str] if @ref_cache[ref_str]

    sha = retry_fresh { rev_parse!(ref_str) }
    make_ref(Armature::Ref::Immutable, ref_str, sha, "tag", name)
    @ref_cache[name] = @ref_cache[ref_str]
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

    command = [ "--git-dir=#{@repo_dir}" ] \
      + work_dir_arguments \
      + arguments

    Armature::Run.clean_git(*command)
  end

  def get_branches()
    freshen()
    data = git("for-each-ref",
      "--format", "%(objectname) %(refname)",
      "refs/heads")
    lines = data.split(/[\r\n]/).reject { |line| line == "" }

    lines.map do |line|
      sha, ref_str = line.split(' ', 2)
      name = ref_str.sub("refs/heads/", "")
      _branch_ref(ref_str, name, sha)
      name
    end
  end

private

  def retry_fresh
    yield
  rescue Armature::RefError
    if @fresh
      raise
    end

    @logger.debug("Got ref error; fetching to see if that helps.")
    freshen()
    yield
  end

  def make_ref(klass, ref_str, sha, type, name)
    @ref_cache[ref_str] = klass.new(self, ref_str, sha, type, name)
  end

  # Get the SHA for a ref, or nil if it doesn't exist
  def rev_parse(ref_str)
    rev_parse!(ref_str)
  rescue Armature::RefError
    nil
  end

  # Get the SHA for a ref, or raise if it doesn't exist
  def rev_parse!(ref_str)
    if @rev_cache[ref_str]
      @rev_cache[ref_str]
    end

    @rev_cache[ref_str] = git("rev-parse", "--verify", "#{ref_str}^{commit}").chomp
  rescue Armature::Run::CommandFailureError
    raise Armature::RefError, "no such ref '#{ref_str}' in repo '#{self}'"
  end

  # Check if a real (full) SHA matches a (possibly partial) candidate SHA
  def sha_match? real, candidate
    real.start_with? candidate
  end
end
