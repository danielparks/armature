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
    logger = Logging.logger[self]

    logger.debug("Run: " + command_to_string(cmd))
    start_time = Time.now
    out, status = Open3.capture2e(environment, *cmd)
    seconds = Time.now - start_time
    logger.debug("Finished " + command_to_string([cmd.first]) + " in #{seconds}: #{status}")

    if ! status.success?
      raise CommandFailureError.new(status, cmd, out)
    end

    out
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
end
