class Armature::Repo
  def self.from_path(cache, path)
    # Called from the cache; don't check for an existing repo
    self.new(cache, path)
  end

  def initialize(cache, repo_dir)
    @cache = cache
    @repo_dir = repo_dir
    @logger = Logging.logger[self]
    @url = nil
    flush_memory!

    @cache.register_repo(self)
  end

  # You may wish to override these methods

  def url
    @url
  end

  def check_out(ref)
  end

  def freshen!
    flush_memory!
  end

  def flush_memory!
    @fresh = false
  end

  # Generally these don't need to be overridden

  def self.type
    self.name.split('::').last().downcase()
  end

  def type
    self.class.type()
  end

  def to_s
    url()
  end

  def freshen
    if ! @fresh
      freshen!
      true
    else
      false
    end
  end
end
