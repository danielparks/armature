module Gofer::Util
  extend self

  ### FIXME better docs
  # check that options only have keys in schema, and use the values as defaults
  #
  #     options = process_options(options, { :output => nil }, { :work_dir => "." })
  def process_options(options, schema, required)
    options = required.merge(schema).merge(options)
    options.each_key do |key|
      if ! schema.has_key? key and ! required.has_key? key
        raise ArgumentError.new("invalid option '#{key}'")
      end
    end
    required.each_key do |key|
      if ! options.hash_key? key
        raise ArgumentError.new("required option '#{key}' not set")
      end
    end
  end
end
