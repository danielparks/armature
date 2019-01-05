require 'open3'
require 'shellwords'

module Armature::Run
  extend self

  class CommandFailureError < Armature::Error
    attr_reader :status
    attr_reader :command
    attr_reader :output

    def initialize(status, command, output)
      @status = status
      @command = command
      @output = output
      super("Command '#{@command.first}' failed with #{@status}")
    end

    def to_s
      command_str = Armature::Run.command_to_string(@command)
      "Command failed: #{command_str}\nReturn: #{@status}\nOutput:\n#{@output}\n"
    end
  end

  def command_to_string(cmd)
    escaped_words = cmd.map do |word|
      escaped = Shellwords.escape(word)
      if escaped == word || word.include?("'") || word.include?("\\")
        escaped
      else
        # The word needs to be quoted, but doesn't contain ' or \. It can just
        # singled-quoted.
        "'#{word}'"
      end
    end

    escaped_words.join(" ")
  end

  def command(environment={}, *cmd)
    pipe_command("", environment, *cmd)
  end

  def pipe_command(input, environment={}, *cmd)
    if input == ""
      logger.debug("Run: " + command_to_string(cmd))
    else
      logger.debug("Run with input: " + command_to_string(cmd))
    end

    # The default doesn't really do anything; it's just there for a little
    # clarity. If we're passed an environment, it will be a Hash. Otherwise,
    # `environment` captured the first value in cmd.
    if ! environment.kind_of?(Hash)
      cmd.unshift(environment)
      environment = {}
    end

    start_time = Time.now
    output, status = nil, nil
    Open3.popen2e(environment, *cmd) do |pipe_in, pipe_out, promise|
      pipe_in.write(input)
      pipe_in.close()
      output = pipe_out.read()
      pipe_out.close()
      status = promise.value
    end
    seconds = Time.now - start_time
    logger.debug("Finished " + command_to_string([cmd.first]) + " in #{seconds}: #{status}")

    if ! status.success?
      raise CommandFailureError.new(status, cmd, output)
    end

    output
  end

  def clean_git(*cmd)
    # Disable general configuration files
    environment = {
      "HOME" => "",
      "XDG_CONFIG_HOME" => "",
      "GIT_CONFIG_NOSYSTEM" => "1",
    }

    command(environment, "git", *cmd)
  end

  def logger
    Logging.logger[self]
  end
end
