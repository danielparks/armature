module Armature::Ref
  class Base
    attr_reader :repo, :canonical_name, :identity, :human_type, :human_name

    def initialize(repo, canonical_name, identity, human_type, human_name)
      @repo = repo
      @canonical_name = canonical_name
      @identity = identity
      @human_type = human_type
      @human_name = human_name
    end

    def check_out
      @repo.check_out(self)
    end

    def to_s
      "#{@human_type} \"#{@human_name}\""
    end
  end
end
