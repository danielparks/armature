module Gofer::Util
  extend self

  ### FIXME better docs
  # check that options only have keys in optional, and use the values as defaults
  #
  #     options = process_options(options, { :output => nil }, { :work_dir => "." })
  def process_options(options, optional, required={})
    options.each_key do |key|
      if ! optional.has_key? key and ! required.has_key? key
        raise ArgumentError.new("invalid option '#{key}'")
      end
    end

    options = required.merge(optional).merge(options)
    required.each_key do |key|
      if options[key].nil?
        raise ArgumentError.new("required option '#{key}' not set")
      end
    end

    options
  end
end
