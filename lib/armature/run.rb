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
      command_str = Armature::Run.command_to_string(*@command)
      "Command failed: #{command_str}\nReturn: #{@status}\nOutput:\n#{@output}\n"
    end
  end

  def command_to_string(*command)
    command.shelljoin
  end

  def command(environment={}, *command)
    logger = Logging.logger[self]

    logger.debug(command_to_string(*command))
    out, status = Open3.capture2e(environment, *command)
    logger.debug(command_to_string(command.first) + ": #{status}")

    if ! status.success?
      raise CommandFailureError.new(status, command, out)
    end

    out
  end

  def clean_git(*command)
    # Disable general configuration files
    environment = {
      "HOME" => "",
      "XDG_CONFIG_HOME" => "",
      "GIT_CONFIG_NOSYSTEM" => "1",
    }

    command(environment, "git", *command)
  end
end
