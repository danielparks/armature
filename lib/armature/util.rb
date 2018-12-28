require "json"
require "net/http"
require "uri"

module Armature::Util
  extend self

  # Validate options passed to a function
  #
  # options - the options that were passed to the function
  # optional - options that are not required as a hash of keys and defaults
  # required - options that are required as a hash of keys and defaults
  #
  # Returns the options hash with defaults applied.
  #
  # ~~~ ruby
  # options = process_options(options, { :output => nil }, { :work_dir => "." })
  # ~~~
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
  #
  # For example, `lock("foo/bar")` creates a `foo/.bar.lock` lock file.
  def lock(path, mode, message=nil)
    lock_path = File.dirname(path) + "/." + File.basename(path) + ".lock"
    lock_file lock_path, mode, message do |lock|
      yield lock
    end
  end

  def lock_file(path, mode, message=nil)
    # Any user that can open the lock file can flock it, causing armature
    # operations to block.
    File.open(path, File::RDWR|File::CREAT, 0600) do |lock|
      if not lock.flock(mode | File::LOCK_NB)
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

  def http_get_json(url, request_headers={})
    accept = { "Accept" => "application/json" }
    body = http_get(url, request_headers.merge(accept))
    JSON.parse(body)
  end

  def http_get_request(url, request_headers={})
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "armature #{Armature::VERSION} #{Armature::HOMEPAGE}"
    request_headers.each do |key, value|
      request[key] = value
    end

    http.request(request)
  end

  def http_get(url, request_headers={})
    start_time = Time.now

    current_url = url
    body = nil

    while body == nil do
      response = http_get_request(current_url, request_headers)
      if response.kind_of? Net::HTTPRedirection
        logger.debug("HTTP redirection: #{current_url} to #{response["Location"].inspect}")
        current_url = response["Location"]
        next
      end

      response.value() # Raise error if we don't get 2xx response
      body = response.body()
    end

    seconds = Time.now - start_time
    logger.debug("Downloaded #{body.length()} bytes from #{current_url} in #{seconds}")

    body
  end

  def logger
    Logging.logger[self]
  end
end
