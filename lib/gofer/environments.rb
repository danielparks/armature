module Gofer
  class Environments
    attr_reader :path

    # path is the path to the directory containing all the environments
    def initialize(path, cache)
      @cache = cache
      @path = path
    end

    def checkout_ref(repo, ref)
      # This will add and update a modules dir in any repo, even if the repo
      # used in a Puppetfile. (Perhaps the cache is used for multiple repos?)
      ref_path = @cache.checkout(repo, ref)

      ### Perhaps this should check for state (completeness) of modules/ and
      ### then skip reading the Puppetfile and just update branches based on
      ### symlink targets?
      puppetfile_path = "#{ref_path}/Puppetfile"
      if File.exist?(puppetfile_path)
        puppetfile = Gofer::Puppetfile.new()
        puppetfile.include(puppetfile_path)
        module_refs = puppetfile.results
      else
        module_refs = {}
      end

      self.apply(ref_path, module_refs)

      @cache.atomic_symlink(ref_path, "#{@path}/#{ref}")
    end

    # Apply the results of the Puppetfile to a ref (e.g. an environment)
    def apply(target_path, module_refs)
      ### validate names and refs for FS safety
      modules_path = "#{target_path}/modules"
      if ! Dir.exist? modules_path
        Dir.mkdir(modules_path)
      end

      module_refs.each do |name, info|
        repo =  @cache.get_repo(info[:git])
        ref_path = @cache.checkout(repo, info[:ref], :name=>"#{name}.#{info[:ref]}")

        puts "#{modules_path}/#{name} -> #{ref_path}"
        @cache.atomic_symlink(ref_path, "#{modules_path}/#{name}")
      end

      Dir.foreach(modules_path) do |name|
        if ! module_refs.has_key? name and name != "." and name != ".."
          # All paths should be symlinks.
          File.delete("#{modules_path}/#{name}")
        end
      end
    end
  end
end
