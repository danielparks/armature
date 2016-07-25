require 'open3'
require 'shellwords'

module Gofer::Run
  extend self

  class CommandFailureError < StandardError
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
      command_str = Gofer::Run.command_to_string(*@command)
      "Command failed: #{command_str}\nReturn: #{@status}\nOutput:\n#{@output}\n"
    end
  end

  def command_to_string(*command)
    command.shelljoin
  end

  def command(*command)
    out, status = Open3.capture2e(*command)
    if ! status.success?
      raise CommandFailureError.new(status, command, out)
    end
    out
  end
end
