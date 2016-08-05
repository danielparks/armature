require 'json'

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

  # Lock a path with a .name.lock file
  def lock(path, mode, message=nil)
    lock_path = File.dirname(path) + "/." + File.basename(path) + ".lock"
    lock_file lock_path, mode, message do |lock|
      yield lock
    end
  end

  def lock_file(path, mode, message=nil)
    # Any user that can open the lock file can flock it, causing gofer
    # operations to block.
    File.open(path, File::RDWR|File::CREAT, 0600) do |lock|
      if not lock.flock(mode | File::LOCK_NB)
        logger = Logging.logger[self]
        logger.info("Waiting for lock on #{path}")

        start_time = Time.now
        lock.flock(mode)
        seconds = Time.now - start_time

        logger.info("Got lock on #{path} after #{seconds} seconds")
      end

      if mode == File::LOCK_EX
        lock.rewind()
        lock.write({
          "pid" => Process.pid,
          "message" => message,
        }.to_json)
        lock.flush()
        lock.truncate(lock.pos)
      elsif message
        raise "message parameter may only be set in File::LOCK_EX mode"
      end

      yield lock
    end
  end
end
