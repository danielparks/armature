module Gofer
  class Environments
    attr_reader :path

    # path is the path to the directory containing all the environments
    def initialize(path, cache, url)
      @cache = cache
      @path = path
      @url = url
      @repo = @cache.get_repo(url)
    end

    def checkout_environment(ref)
      # This will add and update a modules dir in any repo, even if the repo
      # used in a Puppetfile. (Perhaps the cache is used for multiple repos?)
      ref_path = @cache.get_ref_path(@repo, ref)

      ### Perhaps this should check for state (completeness) of modules/ and
      ### then skip reading the Puppetfile and just update branches based on
      ### symlink targets?
      puppetfile_path = "#{ref_path}/Puppetfile"
      if File.exist?(puppetfile_path)
        puppetfile = Gofer::Puppetfile.new(@cache)
        puppetfile.include(puppetfile_path)
        module_refs = puppetfile.results
      else
        module_refs = {}
      end

      self.apply(ref_path, module_refs)

      @cache.atomic_symlink(ref_path, "#{@path}/#{@ref}")
    end

    # Apply the results of the Puppetfile to a ref (e.g. an environment)
    def apply(target_path, module_refs)
      modules_path = "#{target_path}/modules"
      if ! Dir.exist? modules_path
        Dir.mkdir(modules_path)
      end

      module_refs.each do |name, ref_path|
        @cache.atomic_symlink(ref_path, "#{modules_path}/#{@name}")
      end

      Dir.foreach(modules_path) do |name|
        if ! module_refs.has_key? name and name != "." and name != ".."
          ### Assume symlink ok? rm_rf is unsafe
          File.delete("#{modules_path}/#{filename}")
        end
      end
    end
  end
end
